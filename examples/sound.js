const root = getMainScriptDir()
const data = cs.files.read(`${root}/assets/drip.wav`)
var sound = cs.audio.loadWav(data)
for (let i = 0; i < 10; i++) {
    sound.play()
}
