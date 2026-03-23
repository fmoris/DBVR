const express = require('express');
const path = require('path');
const app = express();
const PORT = 3000;

// Servir archivos estáticos desde la carpeta public
app.use(express.static(path.join(__dirname, 'public')));

// Ruta por defecto
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Servidor corriendo en http://0.0.0.0:${PORT}`);
  console.log(`🌐 Acceso local: https://localhost:${PORT}`);
});
