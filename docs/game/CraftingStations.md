# CRAFTING STATION LIFECYCLE:

1. Player Joins
   ├─ PlotService reconciles profile.Data.Plot
   ├─ Plot:LoadFromData reads craftingStations map
   └─ Plot:_loadCraftingStation finds "CraftingStation01" model

2. Craft Started (via RemoteEvent)
   ├─ CraftingService:Craft validates & consumes ingredients
   ├─ CraftingStation:StartCraft sets timer
   ├─ Plot:UpdateProfileData saves to profile
   └─ ProfileStore auto-saves within 5 minutes

3. Player Leaves (Craft Still Active)
   ├─ PlotService:OnPlayerRemoving saves plot data
   └─ profile.Data.Plot.craftingStations[1].activeCraft = { ... }

4. Player Rejoins
   ├─ Plot:LoadFromData restores stations
   ├─ CraftingStation:RestoreActiveCraft resumes craft
   └─ Offline time counted! (uses os.time())

5. Craft Collected
   ├─ CraftingStation:CollectCraft awards items
   ├─ Plot:UpdateProfileData updates profile
   └─ Craft state cleared