function initGraphicsImports(wasm, canvas) {
    const text_decoder = new TextDecoder()
    const text_encoder = new TextEncoder()
    function getString(ptr, len) {
        return text_decoder.decode(wasm.exports.memory.buffer.slice(ptr, ptr+len))
    }

    // Default context options: https://www.khronos.org/registry/webgl/specs/latest/1.0/index.html#WEBGLCONTEXTATTRIBUTES
    const ctx = canvas.getContext('webgl2', {
        // Implement antialias internally with msaa or fxaa.
        // Explicitly set to false since it is true by default and interferes with custom implementations. eg. INVALID_OPERATION when blitting with multisampled framebuffer.
        antialias: false
    })

    const dpr = window.devicePixelRatio || 1;
    let css_width = 0;
    let css_height = 0;

    const unused_res_ids = []
    let next_res_id = 1

    function getNextResId() {
        if (unused_res_ids.length > 0) {
            return unused_res_ids.shift()
        } else {
            const id = next_res_id
            next_res_id += 1
            return id
        }
    }

    function removeResId(id) {
        unused_res_ids.push(id)
    }

    const textures = new Map()
    const framebuffers = new Map()
    const renderbuffers = new Map()
    const vertex_arrays = new Map()
    const shaders = new Map()
    const programs = new Map()
    const buffers = new Map()
    const uniform_locs = new Map()

    return {
        jsSetCanvasBuffer(width, height) {
            canvas.style.width = `${width}px`
            canvas.style.height = `${height}px`
            canvas.width = width * dpr
            canvas.height = height * dpr
            css_width = width
            css_height = height
            return dpr
        },
        jsGlGetUniformLocation(program_id, name_ptr, name_len) {
            const loc = ctx.getUniformLocation(programs.get(program_id), getString(name_ptr, name_len))
            if (!loc.id) {
                loc.id = getNextResId()
                uniform_locs.set(loc.id, loc)
            }
            return loc.id
        },
        jsGlCreateTexture() {
            const id = getNextResId()
            textures.set(id, ctx.createTexture())
            return id
        },
        jsGlEnable(val) {
            ctx.enable(val)
        },
        jsGlDisable(val) {
            ctx.disable(val)
        },
        jsGlBindTexture(target, tex_id) {
            const tex = textures.get(tex_id)
            ctx.bindTexture(target, tex)
        },
        jsGlClearColor(r, g, b, a) {
            ctx.clearColor(r, g, b, a)
        },
        jsGlGetParameterInt(tag) {
            return ctx.getParameter(tag)
        },
        jsGlGetFrameBufferBinding() {
            const cur = ctx.getParameter(ctx.FRAMEBUFFER_BINDING)
            if (cur == null) {
                return 0
            } else {
                return cur.id
            }
        },
        jsGlCreateFramebuffer() {
            const id = getNextResId()
            const fb = ctx.createFramebuffer()
            // Some ops will return the webgl fb object. Record the id on the object so it can map back to a wasm resource id.
            fb.id = id
            framebuffers.set(id, fb)
            return id
        },
        jsGlCreateRenderbuffer() {
            const id = getNextResId()
            renderbuffers.set(id, ctx.createRenderbuffer())
            return id
        },
        jsGlBindFramebuffer(target, id) {
            if (id == 0) {
                ctx.bindFramebuffer(target, null)
            } else {
                ctx.bindFramebuffer(target, framebuffers.get(id))
            }
        },
        jsGlRenderbufferStorageMultisample(target, samples, internalformat, width, height) {
            ctx.renderbufferStorageMultisample(target, samples, internalformat, width, height)
        },
        jsGlBindVertexArray(id) {
            ctx.bindVertexArray(vertex_arrays.get(id))
        },
        jsGlBindBuffer(target, id) {
            ctx.bindBuffer(target, buffers.get(id))
        },
        jsGlEnableVertexAttribArray(index) {
            ctx.enableVertexAttribArray(index)
        },
        jsGlCreateShader(type) {
            const id = getNextResId()
            shaders.set(id, ctx.createShader(type))
            return id
        },
        jsGlShaderSource(id, ptr, len) {
            ctx.shaderSource(shaders.get(id), getString(ptr, len))
        },
        jsGlCompileShader(id) {
            ctx.compileShader(shaders.get(id))
        },
        jsGlGetShaderParameterInt(id, param) {
            return ctx.getShaderParameter(shaders.get(id), param)
        },
        jsGlGetShaderInfoLog(id, buf_size, log_ptr) {
            const log = ctx.getShaderInfoLog(shaders.get(id))
            const wasm_view = new Uint8Array(wasm.exports.memory.buffer)
            const log_utf8 = text_encoder.encode(log).slice(0, buf_size)
            wasm_view.set(log_utf8, log_ptr)
            return log.length
        },
        jsGlDeleteShader(id) {
            ctx.deleteShader(shaders.get(id))
            removeResId(id)
        },
        jsGlCreateProgram() {
            const id = getNextResId()
            programs.set(id, ctx.createProgram())
            return id
        },
        jsGlAttachShader(program_id, shader_id) {
            const program = programs.get(program_id)
            const shader = shaders.get(shader_id)
            ctx.attachShader(program, shader)
        },
        jsGlDetachShader(program_id, shader_id) {
            const program = programs.get(program_id)
            const shader = shaders.get(shader_id)
            ctx.detachShader(program, shader)
        },
        jsGlLinkProgram(id) {
            ctx.linkProgram(programs.get(id))
        },
        jsGlGetProgramParameterInt(id, param) {
            return ctx.getProgramParameter(programs.get(id), param)
        },
        jsGlGetProgramInfoLog(id, buf_size, log_ptr) {
            const log = ctx.getProgramInfoLog(programs.get(id))
            const wasm_view = new Uint8Array(wasm.exports.memory.buffer)
            const log_utf8 = text_encoder.encode(log).slice(0, buf_size)
            wasm_view.set(log_utf8, log_ptr)
            return log.length
        },
        jsGlDeleteProgram(id) {
            ctx.deleteProgram(programs.get(id))
            removeResId(id)
        },
        jsGlCreateVertexArray() {
            const id = getNextResId()
            vertex_arrays.set(id, ctx.createVertexArray())
            return id
        },
        jsGlTexParameteri(target, pname, param) {
            ctx.texParameteri(target, pname, param)
        },
        jsGlTexImage2D(target, level, internal_format, width, height, border, format, type, pixels_ptr) {
            if (pixels_ptr == 0) {
                // Initialize buffer with undefined values.
                ctx.texImage2D(target, level, internal_format, width, height, border, format, type, null)
            } else {
                ctx.texImage2D(target, level, internal_format, width, height, border, format, type, new Uint8Array(wasm.exports.memory.buffer), pixels_ptr)
            }
        },
        jsGlTexSubImage2D(target, level, xoffset, yoffset, width, height, format, type, pixels_ptr) {
            ctx.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, new Uint8Array(wasm.exports.memory.buffer), pixels_ptr)
        },
        jsGlCreateBuffer() {
            const id = getNextResId()
            buffers.set(id, ctx.createBuffer())
            return id
        },
        jsGlVertexAttribPointer(index, size, type, normalized, stride, offset) {
            ctx.vertexAttribPointer(index, size, type, normalized, stride, offset)
        },
        jsGlActiveTexture(tex) {
            // tex is a gl.TEXTUREI and not a resource id.
            ctx.activeTexture(tex)
        },
        jsGlDeleteTexture(id) {
            ctx.deleteTexture(textures.get(id))
            removeResId(id)
        },
        jsGlUseProgram(id) {
            ctx.useProgram(programs.get(id))
        },
        jsGlUniformMatrix4fv(location, transpose, value_ptr) {
            const loc = uniform_locs.get(location)
            const wasm_view = new Uint8Array(wasm.exports.memory.buffer)
            ctx.uniformMatrix4fv(loc, transpose, new Float32Array(wasm_view.slice(value_ptr, value_ptr + 16*4).buffer))
        },
        jsGlUniform1i(location, val) {
            const loc = uniform_locs.get(location)
            ctx.uniform1i(loc, val)
        },
        jsGlBufferData(target, data_ptr, data_size, usage) {
            const wasm_view = new Uint8Array(wasm.exports.memory.buffer)
            ctx.bufferData(target, wasm_view, usage, data_ptr, data_size)
        },
        jsGlDrawElements(mode, num_indices, index_type, index_offset) {
            ctx.drawElements(mode, num_indices, index_type, index_offset)
        },
        jsGlBindRenderbuffer(target, id) {
            ctx.bindRenderbuffer(target, renderbuffers.get(id))
        },
        jsGlFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer) {
            ctx.framebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffers.get(renderbuffer))
        },
        jsGlFramebufferTexture2D(target, attachment, textarget, texture, level) {
            ctx.framebufferTexture2D(target, attachment, textarget, textures.get(texture), level)
        },
        jsGlViewport(x, y, width, height) {
            ctx.viewport(x, y, width, height)
        },
        jsGlClear(mask) {
            ctx.clear(mask)
        },
        jsGlBlendFunc(sfactor, dfactor) {
            ctx.blendFunc(sfactor, dfactor)
        },
        jsGlBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter) {
            ctx.blitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter)
        },
        jsGlBlendEquation(mode) {
            ctx.blendEquation(mode)
        },
        jsGlScissor(x, y, width, height) {
            ctx.scissor(x, y, width, height)
        },
        jsGlCheckFramebufferStatus(target) {
            return ctx.checkFramebufferStatus(target)
        },
        jsGlDeleteVertexArray(id) {
            ctx.deleteVertexArray(vertex_arrays.get(id))
        },
        jsGlDeleteBuffer(id) {
            ctx.deleteBuffer(buffers.get(id))
        },
    }
}