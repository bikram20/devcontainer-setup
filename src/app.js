// app.js - Express Hello World for Dev Container
const express = require('express');
const os = require('os'

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware to log requests
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Main route
app.get('/', (req, res) => {
  res.json({
    message: '🚀 Hello from DigitalOcean Dev Container!',
    environment: {
      isDevContainer: process.env.DEVCONTAINER === 'true',
      nodeVersion: process.version,
      platform: os.platform(),
      hostname: os.hostname(),
      uptime: `${Math.floor(process.uptime())} seconds`
    },
    timestamp: new Date().toISOString()
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', devContainer: true });
});

// Start server
app.listen(PORT, () => {
  console.log('='.repeat(50));
  console.log('🎉 Express Dev Container Server Started!');
  console.log('='.repeat(50));
  console.log(`📦 Running in: ${process.env.DEVCONTAINER ? 'Dev Container' : 'Regular Environment'}`);
  console.log(`🚀 Server listening on port: ${PORT}`);
  console.log(`🔗 Local URL: http://localhost:${PORT}`);
  console.log(`📍 Tunnel: Connected via VS Code tunnel`);
  console.log('='.repeat(50));
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down gracefully...');
  process.exit(0);
});
