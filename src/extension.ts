
import * as vscode from 'vscode';
import * as path from 'path'
import { pick } from './pickProcess';
let extensionDirectory:string

export function activate(context: vscode.ExtensionContext) {
	extensionDirectory = context.extensionPath
	const a = vscode.debug.registerDebugConfigurationProvider("lua", new ResolveConfigurationProvider)
	const b = vscode.debug.registerDebugConfigurationProvider("lua", new InitialConfigurationProvider, vscode.DebugConfigurationProviderTriggerKind.Initial)
	const c = vscode.debug.registerDebugAdapterDescriptorFactory('lua', new DescriptorFactory)
	context.subscriptions.push(a, b, c);
}

class ResolveConfigurationProvider implements vscode.DebugConfigurationProvider {
	async resolveDebugConfiguration(folder: vscode.WorkspaceFolder | undefined, debugConfiguration: vscode.DebugConfiguration, token?: vscode.CancellationToken): Promise<vscode.DebugConfiguration | null | undefined> {
		if (debugConfiguration.request == "attach") {
			debugConfiguration.processId = await pick()
			if (debugConfiguration.processId == "") {
				return
			}
		}
		return debugConfiguration
	}
}

class InitialConfigurationProvider implements vscode.DebugConfigurationProvider {
	provideDebugConfigurations(folder: vscode.WorkspaceFolder | undefined, token?: vscode.CancellationToken): vscode.ProviderResult<vscode.DebugConfiguration[]> {
		return [
			{
				type: 'lua',
				name: "Debug",
				request: "launch",
				runtimeExecutable: "{$workspaceFolder}/lua.exe"
			}
		]
	}
}

class DescriptorFactory implements vscode.DebugAdapterDescriptorFactory {
	createDebugAdapterDescriptor(session: vscode.DebugSession, executable: vscode.DebugAdapterExecutable | undefined): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
		const debugbackend = path.join(extensionDirectory, "bin", "luadebug.exe")
		return new vscode.DebugAdapterExecutable(debugbackend)
	}

}
/**
 * supportsConfigurationDoneRequest
 * supportsFunctionBreakpoints
 * supportsConditionalBreakpoints
 * supportsHitConditionalBreakpoints
 * supportsEvaluateForHovers
 * supportsRestartRequest -- 有bug先不用
 * supportsExceptionInfoRequest
 * supportTerminateDebuggee
 * supportsDelayedStackTraceLoading -- 先不做
 * supportsLoadedSourcesRequest -- 先不用Source机制
 * supportsLogPoints
 * setExpression
 * supportsTerminateRequest
 * supportsClipboardContext 还没做
 * supportsExceptionFilterOptions
 */


export function deactivate() {}
