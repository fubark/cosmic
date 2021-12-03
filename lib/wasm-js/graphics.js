// Js canvas ops.
function initGraphicsImports(wasm, canvas) {
    const ctx = canvas.getContext('2d');

    const text_decoder = new TextDecoder();
    function getString(ptr, len) {
        return text_decoder.decode(wasm.exports.memory.buffer.slice(ptr, ptr+len));
    }

    const fontToName = new Map();
    const nameToFont = new Map();
    const pi_2 = 2 * Math.PI;
    let fillColor = [];
    let strokeColor = [];
    const images = new Map();
    let nextImageId = 1; 

    let wasmBufferView = null;

    function jsGetFont(namePtr, nameLen) {
        const name = getString(namePtr, nameLen).toLowerCase();
        let id = nameToFont.get(name);
        if (!id) {
            id = nameToFont.size + 1;
            nameToFont.set(name, id);
            fontToName.set(id, name);
        }
        return id;
    }

    return {
        jsSetCanvasBuffer(width, height) {
            const dpr = window.devicePixelRatio || 1;
            canvas.style.width = `${width / dpr}px`;
            canvas.style.height = `${height / dpr}px`;
            canvas.width = width;
            canvas.height = height;
            // Start drawing glyphs from top left corner.
            // Needs to be set after changing canvas buffer.
            ctx.textBaseline = 'top';
        },
        jsFillStyle(r, g, b, a) {
            fillColor = [r, g, b, a];
            ctx.fillStyle = `rgba(${r},${g},${b},${a})`;
        },
        jsStrokeStyle(r, g, b, a) {
            strokeColor = [r, g, b, a];
            ctx.strokeStyle = `rgba(${r},${g},${b},${a})`;
        },
        jsFillRect(x, y, width, height) {
            ctx.fillRect(x, y, width, height);
        },
        jsDrawRect(x, y, width, height) {
            ctx.beginPath();
            ctx.rect(x, y, width, height);
            ctx.stroke();
        },
        jsFillCircle(x, y, radius) {
            ctx.beginPath();
            ctx.arc(x, y, radius, 0, pi_2);
            ctx.fill();
        },
        jsDrawCircle(x, y, radius) {
            ctx.beginPath();
            ctx.arc(x, y, radius, 0, pi_2);
            ctx.stroke();
        },
        jsFillCircleSector(x, y, radius, start, end) {
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.arc(x, y, radius, start, end);
            ctx.lineTo(x, y);
            ctx.fill();
        },
        jsDrawCircleArc(x, y, radius, start, end) {
            ctx.beginPath(x, y);
            ctx.arc(x, y, radius, start, end);
            ctx.stroke();
        },
        jsDrawEllipse(x, y, h_radius, v_radius) {
            ctx.beginPath();
            ctx.ellipse(x, y, h_radius, v_radius, 0, 0, pi_2);
            ctx.stroke();
        },
        jsFillEllipse(x, y, h_radius, v_radius) {
            ctx.beginPath();
            ctx.ellipse(x, y, h_radius, v_radius, 0, 0, pi_2);
            ctx.fill();
        },
        jsFillEllipseSector(x, y, h_radius, v_radius, start, end) {
            ctx.beginPath();
            ctx.moveTo(x, y);
            ctx.ellipse(x, y, h_radius, v_radius, 0, start, end);
            ctx.lineTo(x, y);
            ctx.fill();
        },
        jsDrawEllipseArc(x, y, h_radius, v_radius, start, end) {
            ctx.beginPath();
            ctx.ellipse(x, y, h_radius, v_radius, 0, start, end);
            ctx.stroke();
        },
        jsFillTriangle(x1, y1, x2, y2, x3, y3) {
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.lineTo(x3, y3);
            ctx.closePath();
            ctx.fill();
        },
        jsFillPolygon(ptr, num_verts) {
            wasmBufferView = new DataView(wasm.exports.memory.buffer);
            ctx.beginPath();
            var curPtr = ptr;
            const x = wasmBufferView.getFloat32(curPtr, true);
            const y = wasmBufferView.getFloat32(curPtr + 4, true);
            ctx.moveTo(x, y);
            curPtr += 8;
            for (let i = 1; i < num_verts; i++) {
                const x = wasmBufferView.getFloat32(curPtr, true);
                const y = wasmBufferView.getFloat32(curPtr + 4, true);
                ctx.lineTo(x, y);
                curPtr += 8;
            }
            ctx.closePath();
            ctx.fill();
        },
        jsDrawPolygon(ptr, num_verts) {
            wasmBufferView = new DataView(wasm.exports.memory.buffer);
            ctx.beginPath();
            var curPtr = ptr;
            const x = wasmBufferView.getFloat32(curPtr, true);
            const y = wasmBufferView.getFloat32(curPtr + 4, true);
            ctx.moveTo(x, y);
            curPtr += 8;
            for (let i = 1; i < num_verts; i++) {
                const x = wasmBufferView.getFloat32(curPtr, true);
                const y = wasmBufferView.getFloat32(curPtr + 4, true);
                ctx.lineTo(x, y);
                curPtr += 8;
            }
            ctx.closePath();
            ctx.stroke();
        },
        jsDrawRoundRect(x, y, width, height, radius) {
            ctx.beginPath();
            ctx.moveTo(x + radius, y);
            ctx.lineTo(x + width - radius, y);
            ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
            ctx.lineTo(x + width, y + height - radius);
            ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
            ctx.lineTo(x + radius, y + height);
            ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
            ctx.lineTo(x, y + radius);
            ctx.quadraticCurveTo(x, y, x + radius, y);
            ctx.stroke();
        },
        jsFillRoundRect(x, y, width, height, radius) {
            ctx.beginPath();
            ctx.moveTo(x + radius, y);
            ctx.lineTo(x + width - radius, y);
            ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
            ctx.lineTo(x + width, y + height - radius);
            ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
            ctx.lineTo(x + radius, y + height);
            ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
            ctx.lineTo(x, y + radius);
            ctx.quadraticCurveTo(x, y, x + radius, y);
            ctx.fill();
        },
        jsDrawPoint(x, y) {
            ctx.fillStyle = `rgba(${strokeColor[0]},${strokeColor[1]},${strokeColor[2]},${strokeColor[3]})`;
            ctx.fillRect(x - ctx.lineWidth/2, y - ctx.lineWidth/2, ctx.lineWidth, ctx.lineWidth);
            ctx.fillStyle = `rgba(${fillColor[0]},${fillColor[1]},${fillColor[2]},${fillColor[3]})`;
        },
        jsDrawLine(x1, y1, x2, y2) {
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.stroke();
        },
        jsDrawQuadraticBezierCurve(x1, y1, cx, cy, x2, y2) {
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.quadraticCurveTo(cx, cy, x2, y2);
            ctx.stroke();
        },
        jsDrawCubicBezierCurve(x1, y1, c1x, c1y, c2x, c2y, x2, y2) {
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x2, y2);
            ctx.stroke();
        },
        jsSetFontStyle(font_gid, font_size) {
            const name = fontToName.get(font_gid);
            ctx.font = `${font_size}px ${name}`;
        },
        jsFillText(x, y, ptr, len) {
            ctx.fillText(getString(ptr, len), x, y);
        },
        jsSetLineWidth(width) {
            ctx.lineWidth = width;
        },
        jsTranslate(x, y) {
            ctx.translate(x, y);
        },
        jsScale(x, y) {
            ctx.scale(x, y);
        },
        jsRotate(rad) {
            ctx.rotate(rad);
        },
        jsResetTransform() {
            ctx.resetTransform();
        },
        jsFill() {
            ctx.fill();
        },
        jsStroke() {
            ctx.stroke();
        },
        jsClosePath() {
            ctx.closePath();
        },
        jsMoveTo(x, y) {
            ctx.moveTo(x, y);
        },
        jsLineTo(x, y) {
            ctx.lineTo(x, y);
        },
        jsQuadraticCurveTo(cx, cy, x2, y2) {
            ctx.quadraticCurveTo(cx, cy, x2, y2);
        },
        jsCubicCurveTo(c1x, c1y, c2x, c2y, x2, y2) {
            ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x2, y2);
        },
        jsCreateImage(promiseId, ptr, len) {
            // Use fetch so we can detect the image type in the future.
            const svg = getString(ptr, len).endsWith(".svg");
            fetch(getString(ptr, len))
                .then(resp => resp.arrayBuffer())
                .then(buf => {
                    let blob;
                    if (svg) {
                        blob = new Blob([buf], {type: 'image/svg+xml'});
                    } else {
                        blob = new Blob([buf]);
                    }
                    const url = URL.createObjectURL(blob);
                    const img = new Image();
                    const imageId = nextImageId;
                    images.set(imageId, img);
                    nextImageId += 1;
                    img.onload = function() {
                        wasm.exports.wasmResolveImagePromise(promiseId, imageId, this.width, this.height);
                        URL.revokeObjectURL(url);
                    };
                    img.svg = svg;
                    img.src = url;
                });
        },
        jsDrawImageSized(imageId, x, y, width, height) {
            const img = images.get(imageId);
            ctx.drawImage(img, x, y, width, height);
        },
        jsDrawImage(imageId, x, y) {
            const img = images.get(imageId);
            ctx.drawImage(img, x, y);
        },
        jsGetFont: jsGetFont,
        jsAddFont(pathPtr, pathLen, namePtr, nameLen) {
            const path = getString(pathPtr, pathLen);
            const name = getString(namePtr, nameLen);
            const style = document.createElement('style');
            style.textContent = `
                @font-face {
                    font-family: '${name}';
                    src: url('${path}') format('truetype');
                }
            `;
            document.head.append(style);
            return jsGetFont(namePtr, nameLen);
        },
    }
}