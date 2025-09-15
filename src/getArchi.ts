import * as fs from 'fs'
import * as path from 'path'
import {exec} from './utils'

function findInPath(command : string) {
    const pathList = process.env.PATH?.split(path.delimiter)
    if (pathList === undefined) {
        throw new Error("no path find")
    }

    for (const dir of pathList) {
        if (!dir) continue

        const potentialPath = path.join(dir, command)

        if (fs.existsSync(potentialPath)) {
            return potentialPath
        }

        if (process.platform === "win32") {
            const pathExtList = process.env.PATHEXT ? process.env.PATHEXT.split(';') : ['.EXE']
            for (const ext of pathExtList) {
                const potentialPathWithExt = potentialPath + ext;
                if (fs.existsSync(potentialPathWithExt)) {
                    return potentialPathWithExt
                }
            }
        }
    }
    throw new Error("cannot find command in path")
}

export function getArchitectureByExe(executable : string) : string {
    try {
        if (!executable.match(/^[a-zA-Z]:/) && !executable.match(/^\.\\/)) {
            executable = findInPath(executable)
        }
        const fd = fs.openSync(executable, 'r')
        const buffer = Buffer.alloc(1024)

        fs.readSync(fd, buffer, 0, 1024, 0)
        fs.closeSync(fd)

        const dosHeaderSignature = buffer.toString('ascii', 0, 2)
        if (dosHeaderSignature !== 'MZ') {
            throw new Error("Not a valid PE file (DOS signature missing).");
        }

        const peHeaderOffset = buffer.readUInt32LE(0x3C)

        const peSignature = buffer.toString('ascii', peHeaderOffset, peHeaderOffset + 4)
        if (peSignature !== 'PE\0\0') {
            throw new Error("Not a valid PE file (PE signature missing).");
        }

        const machineTypeOffset = peHeaderOffset + 4;
        const machineType = buffer.readUInt16LE(machineTypeOffset);

        switch (machineType) {
        case 0x014c:
            return "x86";
        case 0x8664:
            return "x64"
        default:
            return ""
        }
    } catch (error) {
        return ""
    }
}

export async function getArchitectureByProcessId(processId : string) {
    try {
        const executable = await exec(`wmic process where processid=${processId} get ExecutablePath`)

        const lines = executable.trim().split("\n").map(line => line.trim())

        if (lines.length > 1 && lines[1] !== '') {
            return getArchitectureByExe(lines[1])
        } else {
            return ""
        }
    } catch (error) {
        return ""
    }
}