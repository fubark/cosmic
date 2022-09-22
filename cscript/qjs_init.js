Object.prototype.iterValues = function(cb) {
    for (let val of Object.values(this)) {
        cb(val)
    }
}

Array.prototype.iterValues = function(cb) {
    for (let val of this) {
        cb(val)
    }
}

globalThis._internal = {
    callNamed: function(fn, args, namedArgs) {
        if (!fn.args) {
            fn.args = (fn + '')
                .replace(/[/][/].*$/mg,'') // strip single-line comments
                .replace(/\s+/g, '') // strip white space
                .replace(/[/][*][^/*]*[*][/]/g, '') // strip multi-line comments  
                .split('){', 1)[0].replace(/^[^(]*[(]/, '') // extract the parameters  
                .replace(/=[^,]+/g, '') // strip any ES6 defaults  
                .split(',').filter(Boolean); // split & filter [""]
        }
        for (let i = args.length; i < fn.args.length; i+=1) {
            // If missing, defaults to undefined.
            args.push(namedArgs[fn.args[i]]);
        }
        return fn.apply(undefined, args)
    },
    watchPromise: function(id, promise) {
        promise.then(function (res) {
            globalThis._internal.promiseResolved(id, res)
        })
    },

    tasks: [],
    task_gen: null,

    await_ready: false,
    last_await_value: null,
};
const internal = globalThis._internal
internal.runTasks = function() {
    if (internal.task_gen == null) {
        internal.task_gen = (function* () {
            let i = 0;
            while (i < internal.tasks.length) {
                const res = internal.tasks[i]()
                if (typeof res == 'object' && res[Symbol.iterator]) {
                    yield* res
                }
                i += 1
            }
            internal.tasks.length = 0
        })();
    }
    const res = internal.task_gen.next()
    if (res.done) {
        internal.task_gen = null
        return true
    } else {
        return false
    }
}

internal.awaitSym = Symbol('await')
internal.interruptSym = Symbol('interrupt')

internal.yieldCall = function(fn, thisArg, ...args) {
    const res = fn.call(thisArg, ...args)
    if (fn.constructor.name != 'GeneratorFunction') {
        // Return iterator with one result.
        return {
            [Symbol.iterator]: function() {
                return {
                    next() {
                        return { value: res, done: true }
                    }
                }
            }
        }
    } else {
        return res
    }
}

internal.awaitYield = function(val) {
    if (typeof val == 'object' && val.then) {
        internal.await_ready = false
        val.then(function (res) {
            internal.last_await_value = res
            internal.await_ready = true
        })
    } else {
        internal.last_await_value = val
        internal.await_ready = true
    }
    return internal.awaitSym
}

globalThis.asyncTask = function() {
    const res = {}
    const p = new Promise(resolve => {
        res.resolve = resolve
    })
    res.promise = p
    return res
}

globalThis.queueTask = function(cb) {
    internal.tasks.push(cb)
}

internal.evalGeneratorSrc = function(src) {
    const func = eval(src)
    const gen = func()
    while (true) {
        const res = gen.next(internal.last_await_value)
        if (res.done) {
            return res.value
        }
        if (res.value === internal.awaitSym) {
            internal.runEventLoop()
            while (!internal.await_ready) {
                if (internal.tasks.length == 0) {
                    throw new Error('Unresolved promise')
                }
                internal.runTasks()
                internal.runEventLoop()
            }
        }
    }
}