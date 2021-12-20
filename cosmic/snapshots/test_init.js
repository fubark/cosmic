(function() {

    cs.asserts.eq = function(act, exp) {
        if (equal(act, exp)) {
            return
        }
        throw new Error(`\nActual:\n${format(act)}\nExpected:\n${format(exp)}`)
    }

    cs.asserts.neq = function(act, exp) {
        if (!equal(act, exp)) {
            return
        }
        throw new Error(`\nExpected not equal.\nActual: ${act}\nExpected: ${exp}`)
    }

    function equal(act, exp) {
        if (Object.is(act, exp)) {
            return true
        }
        if (typeof act === 'object' && typeof exp === 'object') {
            if (Object.keys(act || {}).length !== Object.keys(exp || {}).length) {
                return false
            }
            for (const key of Object.getOwnPropertyNames(act)) {
                if (!equal(act[key], exp[key])) {
                    return false
                }
            }
            return true
        }
        return false
    }

    function format(o) {
        return JSON.stringify(o, (key, value) => {
            if (typeof value === 'object') {
                // Recreate the object with keys sorted.
                return Object.keys(value).sort().reduce((obj, key) => {
                    obj[key] = value[key]
                    return obj
                }, {})
            }
            return value
        }, 2)
    }

})();