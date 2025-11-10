const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

io.on('connection', socket => {
  console.log('Client connected:', socket.id);

  socket.on('sender-join', data => console.log('Sender joined:', data));
  socket.on('webrtc-offer', data => { console.log('Offer'); socket.broadcast.emit('webrtc-offer', data); });
  socket.on('webrtc-answer', data => { console.log('Answer'); socket.broadcast.emit('webrtc-answer', data); });
  socket.on('webrtc-ice', data => socket.broadcast.emit('webrtc-ice', data));
  socket.on('mjpeg-frame', data => socket.broadcast.emit('mjpeg-frame', data));

  socket.on('disconnect', () => console.log('Client disconnected:', socket.id));
});

server.listen(3000, () => {
  console.log('Signaling server http://0.0.0.0:3000');
  console.log('Open /viewer.html');
});