```html
<div style="background: gray;">
  <canvas width=300 height=300 id="canvas" ></canvas>
</div>
```

```js

function outlined (aCanvas) {
    var outlineCanvas = aCanvas.cloneNode(),
        border = 4;
  
    outlineCanvas.width = 110;
    outlineCanvas.height = 110;
  
    var outlineCtx = outlineCanvas.getContext('2d');

    outlineCtx.drawImage(aCanvas, 0, 0);
    outlineCtx.drawImage(aCanvas, border, 0);
    outlineCtx.drawImage(aCanvas, border * 2, 0);
    outlineCtx.drawImage(aCanvas, border * 2, border);
    outlineCtx.drawImage(aCanvas, border * 2, border * 2);
    outlineCtx.drawImage(aCanvas, border, border * 2);
    outlineCtx.drawImage(aCanvas, 0, border * 2);
    outlineCtx.drawImage(aCanvas, 0, border);
  
    outlineCtx.globalCompositeOperation = 'source-in';

    outlineCtx.fillStyle = 'gold';
    outlineCtx.fillRect(0,0,110,110);

    outlineCtx.globalCompositeOperation = 'source-over';
    outlineCtx.drawImage(aCanvas, border, border);

    return outlineCanvas;
}

const canvas = document.getElementById("canvas");

rectCanvas = canvas.cloneNode();
rectCanvas.width = 100;
rectCanvas.height = 100;

const ctx = rectCanvas.getContext("2d");

// Blocks
ctx.fillStyle = "blue";
ctx.strokeStyle = "darkblue";

ctx.roundRect(0,0,90,20,5);
ctx.roundRect(0,21,100,20,5);
ctx.roundRect(0,42,50,20,5);

ctx.fill();
ctx.stroke();

canvas.getContext('2d').drawImage(outlined(rectCanvas),10,10);


```
