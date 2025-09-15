import * as child_process from 'child_process'

export function exec(command: string): Promise<string> {
    return new Promise((resolve, reject) => {
        child_process.exec(command, { maxBuffer: 500 * 1024 }, (error, stdout, stderr) => {
            if (error) {
                reject(error)
                return
            }
            if (stderr && stderr.length > 0) {
                reject(new Error(stderr))
                return
            }
            resolve(stdout)
        })
    })
}