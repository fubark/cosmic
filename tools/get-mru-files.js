// get-mru-files.js <dir> <after-unix-epoch>
// Outputs list of files that have been accessed after a given time.
// If reference time is not given, print all files with their access times.
const args = getCliArgs()
const dir = args[2]
const after = args[3] || 0

for (const e of cs.files.walkDir(dir)) {
    const info = cs.files.getPathInfo(e.path)
    if (info.atime > after) {
        if (after) {
            puts(e.path)
        } else {
            puts(e.path, info.atime)
        }
    }
}