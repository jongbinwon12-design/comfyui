#!/usr/bin/env python3
from flask import Flask, request, jsonify, render_template_string
import subprocess
import os
import threading

app = Flask(__name__)

HTML = '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ComfyUI Model Downloader</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        
        .subtitle {
            color: #888;
            margin-bottom: 30px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            margin-bottom: 8px;
            color: #555;
            font-weight: 600;
        }
        
        input, select {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        
        input:focus, select:focus {
            outline: none;
            border-color: #667eea;
        }
        
        button {
            width: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: transform 0.2s;
        }
        
        button:hover {
            transform: translateY(-2px);
        }
        
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none;
        }
        
        .status {
            margin-top: 20px;
            padding: 15px;
            border-radius: 8px;
            display: none;
        }
        
        .status.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
            display: block;
        }
        
        .status.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
            display: block;
        }
        
        .status.info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
            display: block;
        }
        
        .logs {
            margin-top: 20px;
            background: #1e1e1e;
            color: #00ff00;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 300px;
            overflow-y: auto;
            display: none;
        }
        
        .example {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 5px;
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
        
        .info-box {
            background: #e7f3ff;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 5px;
        }
        
        .info-box h3 {
            color: #1976D2;
            margin-bottom: 5px;
        }
        
        .info-box p {
            color: #555;
            font-size: 14px;
            margin: 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎨 ComfyUI Model Downloader</h1>
        <p class="subtitle">Vast.ai 인스턴스에서 모델을 쉽게 다운로드하세요</p>
        
        <div class="info-box">
            <h3>💡 사용 방법</h3>
            <p>Civitai에서 모델 다운로드 URL을 복사해서 붙여넣으세요. 다운로드는 백그라운드에서 진행됩니다.</p>
        </div>
        
        <form id="downloadForm">
            <div class="form-group">
                <label>Civitai URL:</label>
                <input type="text" id="url" placeholder="https://civitai.com/api/download/models/12345..." required>
                <div class="example">예시: https://civitai.com/api/download/models/2514310?type=Model&format=SafeTensor</div>
            </div>
            
            <div class="form-group">
                <label>파일명:</label>
                <input type="text" id="filename" placeholder="my_model.safetensors" required>
                <div class="example">예시: waiIllustrious_v160.safetensors</div>
            </div>
            
            <div class="form-group">
                <label>모델 타입:</label>
                <select id="modelType" required>
                    <option value="checkpoints">Checkpoint</option>
                    <option value="loras">LoRA</option>
                    <option value="vae">VAE</option>
                    <option value="upscale_models">Upscale</option>
                    <option value="controlnet">ControlNet</option>
                </select>
            </div>
            
            <button type="submit">다운로드 시작</button>
        </form>
        
        <div id="status" class="status"></div>
        <div id="logs" class="logs"></div>
    </div>

    <script>
        const form = document.getElementById('downloadForm');
        const statusDiv = document.getElementById('status');
        const logsDiv = document.getElementById('logs');
        
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const url = document.getElementById('url').value;
            const filename = document.getElementById('filename').value;
            const modelType = document.getElementById('modelType').value;
            
            // 버튼 비활성화
            const button = form.querySelector('button');
            button.disabled = true;
            button.textContent = '다운로드 중...';
            
            // 상태 표시
            statusDiv.className = 'status info';
            statusDiv.style.display = 'block';
            statusDiv.textContent = '다운로드를 시작합니다...';
            
            logsDiv.style.display = 'block';
            logsDiv.textContent = '> 다운로드 시작...\n';
            
            try {
                const response = await fetch('/download', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ url, filename, modelType })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    statusDiv.className = 'status success';
                    statusDiv.textContent = '✅ 다운로드가 성공적으로 시작되었습니다!';
                    logsDiv.textContent += result.message + '\n';
                    logsDiv.textContent += '파일 위치: ' + result.path + '\n';
                    logsDiv.textContent += '\n백그라운드에서 다운로드가 진행됩니다.\n';
                    logsDiv.textContent += 'SSH로 접속해서 다운로드 진행 상황을 확인할 수 있습니다:\n';
                    logsDiv.textContent += 'tail -f /var/log/model_downloader.log\n';
                } else {
                    statusDiv.className = 'status error';
                    statusDiv.textContent = '❌ 오류: ' + result.message;
                    logsDiv.textContent += 'ERROR: ' + result.message + '\n';
                }
            } catch (error) {
                statusDiv.className = 'status error';
                statusDiv.textContent = '❌ 오류: ' + error.message;
                logsDiv.textContent += 'ERROR: ' + error.message + '\n';
            } finally {
                button.disabled = false;
                button.textContent = '다운로드 시작';
            }
        });
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/download', methods=['POST'])
def download():
    try:
        data = request.json
        url = data.get('url')
        filename = data.get('filename')
        model_type = data.get('modelType')
        
        if not all([url, filename, model_type]):
            return jsonify({'success': False, 'message': '모든 필드를 입력해주세요'})
        
        # 파일 경로 설정
        base_path = '/workspace/ComfyUI/models'
        file_path = f"{base_path}/{model_type}/{filename}"
        
        # 디렉토리가 없으면 생성
        os.makedirs(f"{base_path}/{model_type}", exist_ok=True)
        
        # Civitai 토큰 추가
        token = os.getenv('CIVITAI_TOKEN', '')
        if token:
            if '?' in url:
                url += f"&token={token}"
            else:
                url += f"?token={token}"
        
        # wget 명령어 실행 (백그라운드)
        cmd = f'wget -O "{file_path}" --show-progress "{url}" >> /var/log/model_downloader.log 2>&1 &'
        
        def run_download():
            subprocess.run(cmd, shell=True)
        
        # 백그라운드에서 다운로드 실행
        thread = threading.Thread(target=run_download)
        thread.daemon = True
        thread.start()
        
        return jsonify({
            'success': True,
            'message': '다운로드가 백그라운드에서 시작되었습니다',
            'path': file_path
        })
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})

if __name__ == '__main__':
    print("Starting Model Downloader on http://0.0.0.0:7860")
    app.run(host='0.0.0.0', port=7860, debug=False)
