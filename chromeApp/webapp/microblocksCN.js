// <script type="text/javascript" src="microblocksCN.js"></script>

function _onkeyevent(evt){
    // console.log(evt.key);
    const prefs = localStorage.getItem('user-prefs');
    const keyboardEvent = JSON.parse(prefs).keyboardEvent;
    if (!keyboardEvent){return}

    let key;
    /*
    // console.log("key:", evt.key);
    switch (evt.key) {
        case 'ArrowLeft':
            key = 'left';
            break;
        case 'ArrowRight':
            key = 'right';
            break;
        case 'ArrowUp':
            key = 'up';
            break;
        case 'ArrowDown':
            key = 'down';
            break;
        default:
            key=evt.key;
    }
    */

    if (evt.type=="keyup") {
        key=evt.key+'-up';
    } else {
        key = evt.key;
    }
    // console.log(key.type);
    const data = new TextEncoder().encode(key);
    const length = data.length + 1;
    const bytes = new Uint8Array([ ...(new Uint8Array([251, 27, 0, length % 256, parseInt((length / 256))])), ...data, ...(new Uint8Array([254]))])
    GP_writeSerialPort(bytes);
}

// document.addEventListener("keypress", _onkeypress);
document.addEventListener("keydown", _onkeyevent);

document.addEventListener("keyup", _onkeyevent);
