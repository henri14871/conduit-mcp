--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local MAX_RECORDING_ATTEMPTS = 10
local RECORDING_RETRY_DELAY = 0.1

local UndoManager = {}

function UndoManager.record(name: string, fn: () -> any): any
	local recording = nil
	local attempts = 0

	while not recording and attempts < MAX_RECORDING_ATTEMPTS do
		recording = ChangeHistoryService:TryBeginRecording("Conduit: " .. name)
		if not recording then
			attempts += 1
			if attempts < MAX_RECORDING_ATTEMPTS then
				task.wait(RECORDING_RETRY_DELAY)
			end
		end
	end

	if not recording then
		error("Could not acquire undo recording lock after " .. MAX_RECORDING_ATTEMPTS .. " attempts for: " .. name)
	end

	local ok, result = pcall(fn)
	if ok then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		return result
	else
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		error(result)
	end
end

function UndoManager.beginTransaction(name: string): any
	local recording = nil
	local attempts = 0

	while not recording and attempts < MAX_RECORDING_ATTEMPTS do
		recording = ChangeHistoryService:TryBeginRecording("Conduit Transaction: " .. name)
		if not recording then
			attempts += 1
			if attempts < MAX_RECORDING_ATTEMPTS then
				task.wait(RECORDING_RETRY_DELAY)
			end
		end
	end

	if not recording then
		error("Could not acquire undo recording lock after " .. MAX_RECORDING_ATTEMPTS .. " attempts for transaction: " .. name)
	end

	return recording
end

function UndoManager.commitTransaction(recording: any)
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end

function UndoManager.rollbackTransaction(recording: any)
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
end

function UndoManager.undo()
	ChangeHistoryService:Undo()
end

function UndoManager.redo()
	ChangeHistoryService:Redo()
end

return UndoManager
