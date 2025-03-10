async function captureImage() {
  const video = document.createElement('video');
  const stream = await navigator.mediaDevices.getUserMedia({ video: true });
  video.srcObject = stream;
  await new Promise((resolve) => video.onloadedmetadata = resolve);
  video.play();

  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  const context = canvas.getContext('2d');
  context.drawImage(video, 0, 0, canvas.width, canvas.height);

  stream.getTracks().forEach(track => track.stop());

  return canvas.toDataURL('image/jpeg');
}
