class "NodeEditor"

require('__shared/NodeCollection')

function NodeEditor:__init()
	self:RegisterEvents()
	self.batchSendTimer = 0
	self.nexBatchSend = 0
	self.playersReceivingNodes = {}
	self.botVision = {}
	self.debugprints = 0
end

function NodeEditor:RegisterEvents()
	NetEvents:Subscribe('NodeEditor:RequestNodes', self, self._onRequestNodes)
	NetEvents:Subscribe('NodeEditor:SendNodes', self, self._onSendNodes)
	NetEvents:Subscribe('UI_Request_Save_Settings', self, self._onUIRequestSaveSettings)
	Events:Subscribe('Level:Loaded', self, self._onLevelLoaded)
	Events:Subscribe('Level:Destroy', self, self._onLevelDestroy)
	Events:Subscribe('Engine:Update', self, self._onEngineUpdate)
	Events:Subscribe('Player:Destroyed', self, self._onPlayerDestroyed)
	Events:Subscribe('Player:Left', self, self._onPlayerLeft)

	NetEvents:Subscribe('NodeEditor:SetBotVision', self, self._onSetBotVision)
	Events:Subscribe('Player:Respawn', self, self._onPlayerRespawn)
	Events:Subscribe('Player:Killed', self, self._onPlayerKilled)
end

function NodeEditor:_onPlayerDestroyed(player)
	self:_stopSendingNodes(player)
end
function NodeEditor:_onPlayerLeft(player)
	self:_stopSendingNodes(player)
end

function NodeEditor:_stopSendingNodes(player)
	for i = 1, #self.playersReceivingNodes do
		if (self.playersReceivingNodes[i].Player.name == player.name) then
			table.remove(self.playersReceivingNodes, i)
			break
		end
	end
end

function NodeEditor:_onLevelDestroy()
	g_NodeCollection:Clear()
end

-- player has requested node collection to be sent
function NodeEditor:_onRequestNodes(player)
	print('NodeEditor:_onRequestNodes: '..tostring(player.name))
	-- tell client to clear their list and how many to expect
	NetEvents:SendToLocal('ClientNodeEditor:ReceivingNodes', player, #g_NodeCollection:Get())
end

-- player has indicated they are ready for nodes to send
function NodeEditor:_onSendNodes(player)
	local nodes = g_NodeCollection:Get()
	table.insert(self.playersReceivingNodes, {Player = player, Index = 1, Nodes = nodes})
	print('Sending '..tostring(#nodes)..' waypoints to '..player.name)
end

function NodeEditor:_onSetBotVision(player, enabled)
	print('NodeEditor:_onSetBotVision ['..player.name..']: '..tostring(enabled))
	self.botVision[player.name] = enabled
	player:Fade(0.5, self.botVision[player.name])
end

function NodeEditor:_onPlayerKilled(player, inflictor, position, weapon, isRoadKill, isHeadShot, wasVictimInReviveState, info)
    if (player ~= nil and self.botVision[player.name]) then
    	player:Fade(0.5, false)
    end
end

function NodeEditor:_onPlayerRespawn(player)
	if (self.botVision[player.name] ~= nil) then
		player:Fade(0.5, self.botVision[player.name])
	end
end

function NodeEditor:_onEngineUpdate(deltaTime, simulationDeltaTime)

	self.batchSendTimer = self.batchSendTimer + deltaTime

	if (self.batchSendTimer > self.nexBatchSend and #self.playersReceivingNodes > 0) then
		self.nexBatchSend = self.batchSendTimer + 0.02 -- milliseconds
		for i = 1, #self.playersReceivingNodes do
			local sendStatus = self.playersReceivingNodes[i]
			local doneThisBatch = 0
			for j = sendStatus.Index, #sendStatus.Nodes do

				local sendableNode = sendStatus.Nodes[j]
				if (type(sendableNode.Next) == 'table') then
					sendableNode.Next = sendableNode.Next.ID
				end
				if (type(sendableNode.Previous) == 'table') then
					sendableNode.Previous = sendableNode.Previous.ID
				end

				NetEvents:SendToLocal('NodeEditor:Create', sendStatus.Player, sendableNode)
				doneThisBatch = doneThisBatch + 1
				sendStatus.Index = j+1
				if (doneThisBatch >= 30) then
					break
				end
			end
			if (sendStatus.Index >= #sendStatus.Nodes) then
				print('Finished sending waypoints to '..sendStatus.Player.name)
				table.remove(self.playersReceivingNodes, i)
				NetEvents:SendToLocal('ClientNodeEditor:Init', sendStatus.Player)
				break
			end
		end
	end
end

-- load waypoints from sql
function NodeEditor:_onLevelLoaded(levelName, gameMode)
	print('NodeEditor:_onLevelLoaded -> '.. levelName..'_'..gameMode)
	g_NodeCollection:Load(levelName .. '_TeamDeathMatch0')

	local counter = 0
	local waypoints = g_NodeCollection:Get()
	for i=1, #waypoints do

		local waypoint = waypoints[i]
		if (type(waypoint.Next) == 'string') then
			counter = counter+1
		end
		if (type(waypoint.Previous) == 'string') then
			counter = counter+1
		end
	end
	print('NodeEditor:_onLevelLoaded -> Stale Nodes: '..tostring(counter))
end

function NodeEditor:_onUIRequestSaveSettings(player, data)
	if Config.disableUserInterface == true then
		return
	end

	if (Config.settingsPassword ~= nil and g_FunBotUIServer:_isAuthenticated(player.accountGuid) ~= true) then
		return;
	end

	local request = json.decode(data);

	if (request.debugTracePaths) then
		-- enabled, send them a fresh list
		self:_onRequestNodes(player)
	else
		-- disabled, delete the client's list
		NetEvents:SendToLocal('NodeEditor:Clear', player)
		NetEvents:SendToLocal('NodeEditor:ClientInit', player)
	end
end

if (g_NodeEditor == nil) then
	g_NodeEditor = NodeEditor()
end

return g_NodeEditor