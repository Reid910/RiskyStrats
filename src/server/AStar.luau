--[[
	A* Pathfinding Module
	Finds the shortest path between two nodes using the A* algorithm
]]

local AStar = {}

-- Calculate cost from one node to another
local function GetCost(fromNode, toNode, goalNode)
	-- Distance to goal (heuristic)
	local toGoal = math.sqrt(
		math.pow(toNode.x - goalNode.x, 2) +
		math.pow(toNode.z - goalNode.z, 2)
	) * 1.1

	-- Distance from current to next
	local length = math.sqrt(
		math.pow(toNode.x - fromNode.x, 2) +
		math.pow(toNode.z - fromNode.z, 2)
	)

	return length, toGoal
end

-- Main pathfinding function
function AStar.FindPath(startNode, endNode, mapGeneration)
	debug.profilebegin("A* Pathfinding")

	-- Quick checks
	if startNode == endNode then
		debug.profileend()
		return {startNode}
	end

	-- Check if directly connected
	if table.find(startNode.connections, endNode.id) then
		debug.profileend()
		return {startNode, endNode}
	end

	-- Track visited nodes with their costs
	local visited = {
		[startNode.id] = {
			cost = 0,
			parentNode = nil
		}
	}

	-- Priority queue for nodes to explore
	local priorityQueue = {{
		node = startNode,
		cost = 0
	}}

	-- Process a connection and update costs
	local function ProcessConnection(currentNode, connectedId)
		local connectedNode = mapGeneration.GetNodeById(connectedId)
		if not connectedNode or connectedNode.deleted then
			return
		end

		local currentCost = visited[currentNode.id].cost
		local length, heuristic = GetCost(currentNode, connectedNode, endNode)
		local totalCost = currentCost + length

		local visitedData = visited[connectedId]
		if visitedData then
			-- Update if we found a better path
			if visitedData.cost > totalCost then
				visited[connectedId] = {
					cost = totalCost,
					parentNode = currentNode
				}
				-- Add to queue again with better cost
				table.insert(priorityQueue, {
					node = connectedNode,
					cost = totalCost + heuristic
				})
			end
		else
			-- First time visiting this node
			visited[connectedId] = {
				cost = totalCost,
				parentNode = currentNode
			}
			table.insert(priorityQueue, {
				node = connectedNode,
				cost = totalCost + heuristic
			})
		end
	end

	-- Main search loop
	local foundGoal = false

	while not foundGoal do
		-- Get the node with lowest cost
		local bestEntry = priorityQueue[1]
		if not bestEntry then
			debug.profileend()
			warn("A* pathfinding failed: No path found")
			return {}
		end

		-- Process all connections
		for _, connectedId in ipairs(bestEntry.node.connections) do
			ProcessConnection(bestEntry.node, connectedId)

			-- Check if we reached the goal
			if connectedId == endNode.id and visited[endNode.id] then
				foundGoal = true
			end
		end

		-- Remove processed node and re-sort
		table.remove(priorityQueue, 1)
		table.sort(priorityQueue, function(a, b)
			return a.cost < b.cost
		end)
	end

	-- Reconstruct path from end to start
	local path = {endNode}
	local currentData = visited[endNode.id]

	while currentData.parentNode do
		table.insert(path, currentData.parentNode)
		if currentData.parentNode == startNode then
			break
		end
		currentData = visited[currentData.parentNode.id]
	end

	-- Reverse path to go from start to end
	local finalPath = {}
	for i = #path, 1, -1 do
		table.insert(finalPath, path[i])
	end

	debug.profileend()

	return finalPath
end

return AStar
