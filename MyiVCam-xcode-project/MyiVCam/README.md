# MyiVCam (iOS App native, type iVCam)

App iOS (UIKit, Swift 5, iOS 15+) transformant l’iPhone en webcam réseau:
- WebRTC (faible latence, codec H.264 préféré)
- Fallback MJPEG
- Fallback RTMP (optionnel, requiert un serveur RTMP côté PC)

## 1) Compilation (si tu as un Mac)
1. Installer CocoaPods: `sudo gem install cocoapods`
2. `cd MyiVCam-xcode-project`
3. `pod install`
4. Ouvrir `MyiVCam.xcworkspace` avec Xcode
5. Dans Target > Signing, mettre ton Bundle ID + compte Apple
6. Sélectionner ton iPhone et `Run` (⌘R)

## 2) Export .ipa (pour AltStore)
1. Product > Archive
2. Distribute > Development
3. Sauvegarder le `.ipa`

Tes amis peuvent installer via AltStore: AltStore > Mes Apps > “+” > choisir l’IPA.

## 3) Pas de Mac ? (Windows uniquement)
Utilise GitHub Actions pour builder l’IPA automatiquement sur un runner macOS:
- Ajoute le workflow `.github/workflows/build-ipa.yml` (fourni dans la réponse)
- Ajoute les secrets (certificat .p12, profil .mobileprovision, TEAM_ID)
- Lance le workflow → télécharge l’IPA artifact
- AltStore sur iPhone → “+” → installer l’IPA

## 4) Serveur de signalisation (PC)
Dans `server/` (fourni):
```bash
npm install
node server.js
```
Ouvre `http://PC_IP:3000/viewer.html` sur le PC.

## 5) Utilisation
- Ouvre l’app sur iPhone
- Tape `PC_IP:3000` (ex: `192.168.1.10:3000`)
- Mode `WebRTC`
- Connect → Start
- La vidéo apparaît sur `viewer.html`

## Ports
- 3000/TCP: signalisation + pages viewer
- 1935/TCP: RTMP (si utilisé)
- WebRTC utilise des ports UDP locaux (LAN)

## Dépannage
- Firewall Windows: autoriser port 3000
- Même réseau Wi-Fi
- Autorisations iOS (Caméra, Micro)
- STUN (optionnel hors LAN): ajouter `stun:stun.l.google.com:19302` dans `WebRTCManager.rtcConfig`