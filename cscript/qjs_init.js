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
};

globalThis.asyncTask = function() {
    const res = {}
    const p = new Promise(resolve => {
        res.resolve = resolve
    })
    res.promise = p
    return res
}