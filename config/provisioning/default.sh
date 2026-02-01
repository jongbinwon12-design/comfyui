#!/bin/bash

# This file will be sourced in init.sh

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
)

# 체크포인트 모델
# 형식: "URL|원하는파일명.safetensors"
CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/2514310?type=Model&format=SafeTensor&size=pruned&fp=fp16|waiIllustrious_v160.safetensors"
)

UNET_MODELS=()

# LoRA 모델  
# 형식: "URL|원하는파일명.safetensors"
LORA_MODELS=(
    "https://civitai.com/api/download/models/1266729?type=Model&format=SafeTensor|makima_chainsaw_man.safetensors"
    "https://civitai.com/api/download/models/2625886?type=Model&format=SafeTensor|instant_loss_2col.safetensors"
    "https://civitai.com/api/download/models/2620727?type=Model&format=SafeTensor|진천우.safetensors"
)

# VAE 모델
# 형식: "URL|원하는파일명.safetensors"
VAE_MODELS=(
    "https://civitai.com/api/download/models/333245?type=Model&format=SafeTensor|sdxl_vae_fp16.safetensors"
)

UPSCALE_MODELS=(

)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

### 모델 다운로더 웹 UI 설정 ###
function setup_model_downloader() {
    echo "Setting up Model Downloader Web UI..."
    
    # Flask 설치
    pip install flask --quiet 2>/dev/null || true
    
    # Python 스크립트가 같은 디렉토리에 있는지 확인
    local script_path="$(dirname "${BASH_SOURCE[0]}")/model_downloader.py"
    if [[ -f "$script_path" ]]; then
        cp "$script_path" /tmp/model_downloader.py
        chmod +x /tmp/model_downloader.py
        echo "Model downloader script copied"
    else
        echo "Warning: model_downloader.py not found at $script_path"
    fi
}

function provisioning_start() {
    # 환경 스크립트가 있으면 실행, 없으면 무시
    if [[ -f /opt/ai-dock/etc/environment.sh ]]; then
        source /opt/ai-dock/etc/environment.sh
    fi
    
    if [[ -f /opt/ai-dock/bin/venv-set.sh ]]; then
        source /opt/ai-dock/bin/venv-set.sh comfyui
    fi
    
    # WORKSPACE 기본값 설정
    if [[ -z "${WORKSPACE}" ]]; then
        export WORKSPACE="/workspace"
    fi

    provisioning_print_header
    setup_model_downloader  # ← 이 줄 추가
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/upscale_models" \
        "${UPSCALE_MODELS[@]}"
    
    # 모델 다운로더 웹 UI 시작 (백그라운드) ← 이 섹션 추가
    if [[ -f /tmp/model_downloader.py ]]; then
        echo "Starting Model Downloader Web UI on port 7860..."
        nohup python3 /tmp/model_downloader.py > /var/log/model_downloader.log 2>&1 &
        echo "Model Downloader Web UI started"
    fi
    
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
        path="/opt/ComfyUI/custom_nodes/${dir}"
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

function provisioning_get_default_workflow() {
    if [[ -n $DEFAULT_WORKFLOW ]]; then
        workflow_json=$(curl -s "$DEFAULT_WORKFLOW")
        if [[ -n $workflow_json ]]; then
            echo "export const defaultGraph = $workflow_json;" > /opt/ComfyUI/web/scripts/defaultGraph.js
        fi
    fi
}

function provisioning_get_models() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Web UI will start now\n\n"
}

function provisioning_download() {
    local url_with_filename="$1"
    local dir="$2"
    
    local url
    local filename
    
    if [[ "$url_with_filename" == *"|"* ]]; then
        url="${url_with_filename%%|*}"
        filename="${url_with_filename##*|}"
        echo "Using custom filename: $filename"
    else
        url="$url_with_filename"
        local model_id=$(echo "$url" | grep -oP 'models/\K[0-9]+')
        filename="${model_id}.safetensors"
        echo "Using model ID as filename: $filename"
    fi
    
    echo "Downloading from: $url"
    echo "To directory: $dir"
    echo "Saving as: $filename"
    
    if [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        echo "Using Civitai token"
        if [[ $url == *"?"* ]]; then
            url="${url}&token=${CIVITAI_TOKEN}"
        else
            url="${url}?token=${CIVITAI_TOKEN}"
        fi
    elif [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        echo "Using HuggingFace token (header method)"
        wget --header="Authorization: Bearer $HF_TOKEN" \
             -O "${dir}/${filename}" \
             --show-progress \
             --timeout=60 \
             --tries=3 \
             "$url" 2>&1
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "ERROR: Download failed with exit code $exit_code"
            rm -f "${dir}/${filename}"
        else
            echo "SUCCESS: Downloaded as ${filename}"
        fi
        ls -lh "$dir"
        return $exit_code
    fi
    
    wget -O "${dir}/${filename}" \
         --show-progress \
         --timeout=60 \
         --tries=3 \
         "$url" 2>&1
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Download failed with exit code $exit_code"
        rm -f "${dir}/${filename}"
    else
        echo "SUCCESS: Downloaded as ${filename}"
    fi
    
    ls -lh "$dir"
    return $exit_code
}

provisioning_start
