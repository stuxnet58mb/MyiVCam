# create-server.ps1
$ErrorActionPreference = "Stop"
$root = Get-Location
$serverPath = Join-Path $root "server"
$publicPath = Join-Path $serverPath "public"
New-Item -ItemType Directory -Force -Path $serverPath | Out-Null
New-Item -ItemType Directory -Force -Path $publicPath | Out-Null

@'
{
  "name": "myivcam-signal-server",
  "version": "1.0.0",
  "description": "Signaling server for MyiVCam WebRTC + MJPEG fallback",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.19.2",
    "socket.io": "^4.7.5"
  }
}
'@ | Set-Content -Path (Join-Path $serverPath "package.json") -Encoding UTF8

@'
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
app.use(express.static(path.join(__dirname, 'public')));
io.on('connection', socket => {
  console.log('Client connected:', socket.id);
  socket.on('sender-join', d => console.log('Sender join', d));
  socket.on('webrtc-offer', d => { console.log('Offer'); socket.broadcast.emit('webrtc-offer', d); });
  socket.on('webrtc-answer', d => { console.log('Answer'); socket.broadcast.emit('webrtc-answer', d); });
  socket.on('webrtc-ice', d => socket.broadcast.emit('webrtc-ice', d));
  socket.on('mjpeg-frame', d => socket.broadcast.emit('mjpeg-frame', d));
});
server.listen(3000, () => console.log('Signal server http://0.0.0.0:3000'));
'@ | Set-Content -Path (Join-Path $serverPath "server.js") -Encoding UTF8

@'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Viewer</title>
<style>body{font-family:Arial;background:#111;color:#eee}video,img{width:640px;max-width:100%;background:#000}</style>
</head><body>
<h1>Viewer</h1><div id="status">Connecting...</div>
<select id="modeSelect"><option value="webrtc">WebRTC</option><option value="mjpeg">MJPEG</option></select>
<video id="webrtcVideo" autoplay playsinline></video>
<img id="mjpegImage" style="display:none;">
<script src="/socket.io/socket.io.js"></script>
<script>
const socket=io();const statusEl=document.getElementById('status');
const videoEl=document.getElementById('webrtcVideo');const mjpegImg=document.getElementById('mjpegImage');
const modeSelect=document.getElementById('modeSelect');let pc=null;
function setup(){pc=new RTCPeerConnection();pc.ontrack=e=>{videoEl.srcObject=e.streams[0];};
pc.onicecandidate=e=>{if(e.candidate){socket.emit('webrtc-ice',{candidate:e.candidate.candidate,sdpMLineIndex:e.candidate.sdpMLineIndex,sdpMid:e.candidate.sdpMid});}};}
socket.on('connect',()=>statusEl.textContent='Socket connected.');
socket.on('webrtc-offer',async d=>{if(modeSelect.value!=='webrtc')return;setup();await pc.setRemoteDescription({type:'offer',sdp:d.sdp});
const ans=await pc.createAnswer();await pc.setLocalDescription(ans);socket.emit('webrtc-answer',{sdp:ans.sdp});statusEl.textContent='Answer sent.';});
socket.on('webrtc-ice',async d=>{if(!pc)return;try{await pc.addIceCandidate({candidate:d.candidate,sdpMLineIndex:d.sdpMLineIndex,sdpMid:d.sdpMid});}catch(e){console.error(e);} });
socket.on('mjpeg-frame',d=>{if(modeSelect.value!=='mjpeg')return;mjpegImg.style.display='block';videoEl.style.display='none';mjpegImg.src='data:image/jpeg;base64,'+d.image;});
modeSelect.onchange=()=>{if(modeSelect.value==='webrtc'){mjpegImg.style.display='none';videoEl.style.display='block';statusEl.textContent='WebRTC mode.'}else{statusEl.textContent='MJPEG mode.'}};
</script></body></html>
'@ | Set-Content -Path (Join-Path $publicPath "viewer.html") -Encoding UTF8

@'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Sender Debug</title>
<style>body{font-family:Arial;background:#222;color:#eee}video{width:320px;background:#000}</style></head>
<body><h1>Sender Debug</h1><div id="status">Init...</div><video id="localVideo" autoplay playsinline muted></video>
<script src="/socket.io/socket.io.js"></script><script>
const socket=io();const statusEl=document.getElementById('status');
let pc=new RTCPeerConnection();
navigator.mediaDevices.getUserMedia({video:true,audio:true}).then(s=>{document.getElementById('localVideo').srcObject=s;s.getTracks().forEach(t=>pc.addTrack(t,s));});
pc.onicecandidate=e=>{if(e.candidate){socket.emit('webrtc-ice',{candidate:e.candidate.candidate,sdpMLineIndex:e.candidate.sdpMLineIndex,sdpMid:e.candidate.sdpMid});}};
socket.on('connect',()=>{statusEl.textContent='Socket ok';createOffer();});
socket.on('webrtc-answer',async d=>{await pc.setRemoteDescription({type:'answer',sdp:d.sdp});statusEl.textContent='Answer set.';});
socket.on('webrtc-ice',async d=>{try{await pc.addIceCandidate({candidate:d.candidate,sdpMLineIndex:d.sdpMLineIndex,sdpMid:d.sdpMid});}catch(e){console.error(e);} });
async function createOffer(){const off=await pc.createOffer();await pc.setLocalDescription(off);socket.emit('webrtc-offer',{sdp:off.sdp});statusEl.textContent='Offer sent.';}
</script></body></html>
'@ | Set-Content -Path (Join-Path $publicPath "sender.html") -Encoding UTF8

Write-Host "✅ Serveur généré. Étapes suivantes:"
Write-Host "cd server"
Write-Host "npm install"
Write-Host "node server.js"