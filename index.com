<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NOW - Camera</title>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }

    body {
      background-color: #09090b;
      color: #ffffff;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      overflow: hidden;
    }

    .app-viewport {
      width: 100%;
      max-width: 430px;
      height: 100vh;
      max-height: 932px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      padding: 20px;
      position: relative;
    }

    /* Top Bar */
    .header {
      text-align: center;
      font-weight: 900;
      letter-spacing: 3px;
      font-size: 1.5rem;
      padding: 10px 0;
      color: #f4f4f5;
    }

    /* Camera View Container */
    .media-container {
      position: relative;
      width: 100%;
      flex: 1;
      border-radius: 28px;
      overflow: hidden;
      background: #18181b;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    video, img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }

    /* UI Controls */
    .controls {
      height: 120px;
      display: flex;
      justify-content: center;
      align-items: center;
    }

    /* Shutter Button */
    .shutter-btn {
      width: 76px;
      height: 76px;
      border-radius: 50%;
      border: 4px solid #ffffff;
      background: transparent;
      padding: 4px;
      cursor: pointer;
      transition: transform 0.1s ease;
    }

    .shutter-btn:active {
      transform: scale(0.92);
    }

    .shutter-inner {
      width: 100%;
      height: 100%;
      background: #ffffff;
      border-radius: 50%;
    }

    /* Preview State (Overlay) */
    .preview-overlay {
      display: none;
      flex-direction: column;
      gap: 12px;
      width: 100%;
      position: absolute;
      bottom: 20px;
      padding: 0 16px;
    }

    .caption-input {
      width: 100%;
      padding: 14px 18px;
      border-radius: 16px;
      border: 1px solid rgba(255, 255, 255, 0.2);
      background: rgba(0, 0, 0, 0.65);
      backdrop-filter: blur(12px);
      color: #fff;
      font-size: 0.95rem;
      outline: none;
      text-align: right;
    }

    .send-btn {
      width: 100%;
      padding: 16px;
      border-radius: 16px;
      border: none;
      background: #ffffff;
      color: #000000;
      font-weight: 700;
      font-size: 1rem;
      cursor: pointer;
      transition: opacity 0.2s;
    }

    .send-btn:active {
      opacity: 0.85;
    }
  </style>
</head>
<body>

  <div class="app-viewport">
    <div class="header">NOW</div>

    <!-- Media Area -->
    <div class="media-container">
      <video id="webcam" autoplay playsinline muted></video>
      <img id="captured-preview" style="display: none;" alt="Captured Instant" />
      
      <!-- Preview Options (Caption & Send) -->
      <div class="preview-overlay" id="preview-controls">
        <input type="text" id="caption-input" class="caption-input" placeholder="اكتب حاجة هنا..." maxlength="60" />
        <button id="send-btn" class="send-btn">SEND ⚡</button>
      </div>
    </div>

    <!-- Shutter Control -->
    <div class="controls" id="camera-controls">
      <button class="shutter-btn" id="shutter-btn">
        <div class="shutter-inner"></div>
      </button>
    </div>
  </div>

  <!-- Hidden Canvas for frame processing -->
  <canvas id="capture-canvas" style="display: none;"></canvas>

  <script>
    const webcam = document.getElementById('webcam');
    const shutterBtn = document.getElementById('shutter-btn');
    const canvas = document.getElementById('capture-canvas');
    const capturedPreview = document.getElementById('captured-preview');
    const cameraControls = document.getElementById('camera-controls');
    const previewControls = document.getElementById('preview-controls');
    const sendBtn = document.getElementById('send-btn');
    const captionInput = document.getElementById('caption-input');

    let preparedFile = null; // الملف النهائي اللي هيترفع للـ Storage

    // 1. فتح الكاميرا
    async function startCamera() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: 'user', // استخدام الكاميرا الأمامية (أو 'environment' للخلفية)
            width: { ideal: 1080 },
            height: { ideal: 1920 }
          },
          audio: false
        });
        webcam.srcObject = stream;
      } catch (err) {
        alert("يرجى إعطاء صلاحية الكاميرا لعمل التطبيق.");
        console.error("Camera access error:", err);
      }
    }

    // 2. التقاط الصورة (No Retake Workflow)
    shutterBtn.addEventListener('click', () => {
      if (!webcam.srcObject) return;

      // ضبط أبعاد الـ Canvas حسب أبعاد الفيديو الحقيقية
      canvas.width = webcam.videoWidth;
      canvas.height = webcam.videoHeight;

      const ctx = canvas.getContext('2d');
      
      // رسم إطار الكاميرا داخل الـ Canvas
      ctx.drawImage(webcam, 0, 0, canvas.width, canvas.height);

      // تحويل الصورة لـ Blob بفرومات WebP مضغوطة وعالية الجودة
      canvas.toBlob((blob) => {
        if (!blob) return;

        // تحويل الـ Blob إلى File جاهز للرفع لـ Supabase
        preparedFile = new File([blob], `instant_${Date.now()}.webp`, { type: 'image/webp' });

        // عرض المعاينة وإيقاف إطار الكاميرا
        capturedPreview.src = URL.createObjectURL(blob);
        capturedPreview.style.display = 'block';
        webcam.style.display = 'none';

        // تبديل أزرار الواجهة
        cameraControls.style.display = 'none';
        previewControls.style.display = 'flex';
      }, 'image/webp', 0.85);
    });

    // 3. الإرسال (جاهز للربط مع Supabase)
    sendBtn.addEventListener('click', () => {
      const caption = captionInput.value.trim();
      
      console.log("File to upload:", preparedFile);
      console.log("Caption text:", caption);

      alert("تم تجهيز الصورة بنجاح! جاهزة للرفع على Supabase.");
    });

    // تشغيل الكاميرا فور تحميل الصفحة
    startCamera();
  </script>
</body>
</html>
