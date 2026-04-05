--!strict

export type BridgeRequest = {
	id: string,
	method: string,
	params: { [string]: any },
}

export type BridgeResponse = {
	id: string,
	result: any,
	tokenEstimate: number?,
}

export type BridgeError = {
	id: string,
	error: {
		code: string,
		message: string,
	},
}

export type Heartbeat = {
	type: "heartbeat",
}

export type HandlerFn = (params: { [string]: any }) -> any

return nil
