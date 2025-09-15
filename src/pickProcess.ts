import * as vscode from 'vscode'
import * as os from 'os'
import {exec} from './utils'
interface ProcessEntry {
    label: string,
    description: string,
    detail: string
}
async function WimcProcess(name: string | undefined, processEntries: ProcessEntry[]) {
    const processes = await exec("wmic process get commandline,name,processid /FORMAT:list")
    const lines = processes.split(os.EOL)
    let process: { [key: string]: string } = {}
    for (let line of lines) {
        const res = line.match(/^(.*?)=\s*(.*)\s*$/);
        if (res) {
            process[res[1]] = res[2]
        }
        else {
            if (process.Name && (name === undefined || name === process.Name)) {
                processEntries.push({
                    label: process.Name,
                    description: process.ProcessId,
                    detail: process.CommandLine
                })
                process = {}
            }
        }
    }
    return process;
}

async function getlist(name: string | undefined) {
    const processEntries: ProcessEntry[] = [];
    await WimcProcess(name, processEntries);
    processEntries.sort((a, b) => {
        const aLower = a.label.toLowerCase();
        const bLower = b.label.toLowerCase();
        if (aLower === bLower) {
            return 0;
        }
        return aLower < bLower ? -1 : 1;
    })

    return processEntries
}

export async function pick() {
    const process = await vscode.window.showQuickPick(getlist(undefined), {placeHolder:"Select process to attach to"})
    if (process) {
        return process.description
    }
    return ""
}