const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

console.log('Generando certificado HTTPS...');

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
});

const cert = crypto.createSign('SHA256');
cert.update('CN=192.168.3.30');
const certPEM = cert.sign(privateKey, 'pem');

// Guardar
fs.writeFileSync(path.join(__dirname, 'key.pem'), privateKey);
fs.writeFileSync(path.join(__dirname, 'cert.pem'), certPEM);

console.log('✅ Certificados generados');