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
    
    # 1. Flask 설치 (가상환경 내부)
    pip_install flask
    
    # 2. 파일 자동 다운로드 (직접 업로드 대신 URL에서 가져오기)
    # 아래 URL 부분에 실제 model_downloader.py 파일이 올라가 있는 주소를 넣으세요.
    local download_url="https://raw.githubusercontent.com/jongbin03/model_downloader/refs/heads/main/model_downloader.py"
    
    echo "Downloading model_downloader.py from $download_url..."
    wget -O /tmp/model_downloader.py "$download_url"
    
    if [[ -f "/tmp/model_downloader.py" ]]; then
        chmod +x /tmp/model_downloader.py
        echo "Model downloader script successfully downloaded to /tmp"
    else
        echo "Error: Failed to download model_downloader.py"
    fi
}

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
    
    # 1. 스크립트 복사 및 Flask 설치 실행 
    setup_model_downloader
    
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    
    # 2. 기존 모델 다운로드 시퀀스 (동일) 
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    # ... (중략) ...
    provisioning_get_models \
        "${WORKSPACE}/ComfyUI/models/upscale_models" \
        "${UPSCALE_MODELS[@]}"
    
    # 3. 모델 다운로더 웹 UI 시작 
    if [[ -f /tmp/model_downloader.py ]]; then
        echo "Starting Model Downloader Web UI on port 7860..."
        # 가상환경의 python을 사용하여 nohup 실행, 로그는 /workspace에 저장
        nohup python /tmp/model_downloader.py > /workspace/model_downloader_server.log 2>&1 &
        echo "Model Downloader Web UI started. Log: /workspace/model_downloader_server.log"
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
