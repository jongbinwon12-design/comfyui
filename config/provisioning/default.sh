#!/bin/bash

# This file will be sourced in init.sh

# 설치할 커스텀 노드 목록
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/willmiao/ComfyUI-Lora-Manager"
    "https://github.com/jags111/efficiency-nodes-comfyui"
    "https://github.com/NyaamZ/efficiency-nodes-ED"
    "https://github.com/rgthree/rgthree-comfy"
)

# 체크포인트 모델
CHECKPOINT_MODELS=(
)
 
ZIT_MODELS=(
    "https://civitai.com/api/download/models/2633363?type=Model&format=SafeTensor&size=full&fp=fp16|moodyPornMix_zitV7.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/z_image/resolve/main/split_files/text_encoders/qwen_3_4b_fp8_mixed.safetensors|/qwen_3_4b_fp8_mixed.safetensors"
)

UNET_MODELS=()

# LoRA 모델 (이 부분이 다시 작동하는지 확인하세요)
LORA_MODELS=(
    "https://civitai.com/api/download/models/2607212?type=Model&format=SafeTensor|NSFW_master_ZIT_000008766.safetensors"
)

CONTROLNET_MODELS=(
    "https://civitai.com/api/download/models/158658?type=Model&format=SafeTensor|OpenPoseXL2.safetensors"
)

# VAE 모델
VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors|ae.safetensors"
)

UPSCALE_MODELS=(
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth|4x_NMKD-Siax_200k.pth"
)

LATENT_UPSCALE_MODELS=(
)

PIP_PACKAGES=(
    "piexif"
    "opencv-python-headless"
    "simpleeval"
    "scikit-image"
    "ultralytics"
)

### 운영 로직 (수정하지 마세요) ###

function provisioning_start() {
    # 환경 설정 및 가상환경 활성화
    if [[ -f /opt/ai-dock/etc/environment.sh ]]; then
        source /opt/ai-dock/etc/environment.sh
    fi
    
    if [[ -f /opt/ai-dock/bin/venv-set.sh ]]; then
        source /opt/ai-dock/bin/venv-set.sh comfyui
    fi
    
    if [[ -z "${WORKSPACE}" ]]; then
        export WORKSPACE="/workspace"
    fi

    provisioning_print_header
    
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    
    # 모델 다운로드 실행
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/upscale_models" \
        "${UPSCALE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/latent_upscale_models" \
        "${LATENT_UPSCALE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    # Diffusion Models (Anima 등)
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/diffusion_models" \
        "${DIFFUSION_MODELS[@]}"
    # Text Encoders (CLIP, T5, Qwen 등)
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/clip" \
        "${TEXT_ENCODERS[@]}"
    
    provisioning_print_end
}

function pip_install() {
    if [[ -z $MAMBA_BASE ]]; then
        "$COMFYUI_VENV_PIP" install --no-cache-dir "$@"
    else
        micromamba run -n comfyui pip install --no-cache-dir "$@"
    fi
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
        pip_install ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        # 경로를 시스템 영역(/opt)에서 사용자 작업 영역(${WORKSPACE})으로 수정
        path="${WORKSPACE}/ComfyUI/custom_nodes/${dir}"
        
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip_install -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip_install -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_models() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    for url in "${arr[@]}"; do
        provisioning_download "${url}" "${dir}"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#          Provisioning container            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete\n\n"
}

function provisioning_download() {
    local url_with_filename="$1"
    local dir="$2"
    local url
    local filename
    
    if [[ "$url_with_filename" == *"|"* ]]; then
        url="${url_with_filename%%|*}"
        filename="${url_with_filename##*|}"
    else
        url="$url_with_filename"
        filename="model.safetensors"
    fi
    
    # Civitai 토큰 처리
    if [[ -n $CIVITAI_TOKEN && $url =~ civitai\.com ]]; then
        if [[ $url == *"?"* ]]; then url="${url}&token=${CIVITAI_TOKEN}"; else url="${url}?token=${CIVITAI_TOKEN}"; fi
    fi
    
    wget -O "${dir}/${filename}" --show-progress "$url"
}

provisioning_start
