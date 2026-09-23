------------------------------------------------------------------------------
--	FILE:	 West_vs_East.lua
--	AUTHOR:  Bob Thomas
--	PURPOSE: Regional map script - Designed to pit two teams against each other
--	         with a strip of water dividing the map east from west.
------------------------------------------------------------------------------
--	Copyright (c) 2010 Firaxis Games, Inc. All rights reserved.
------------------------------------------------------------------------------

include("DEFMapGeneratorW8");
include("DEFMultilayeredFractalW");
include("DEFFeatureGeneratorW");
include("DEFTerrainGeneratorW");

print("Weevee Map 11.0.15 script loaded");

local weeveeDbgHandle = nil;
local WEEVEE_DBG_PATHS = {
	"C:\\Users\\bbruno\\Documents\\My Games\\Sid Meier's Civilization 5\\Logs\\weevee_dbg.log",
	"weevee_dbg.log",
};
function WeeveeDbgOpen(mode)
	if weeveeDbgHandle ~= nil then
		weeveeDbgHandle:close();
		weeveeDbgHandle = nil;
	end
	if io == nil or io.open == nil then
		return
	end
	local i = 1;
	while i <= #WEEVEE_DBG_PATHS do
		local f = io.open(WEEVEE_DBG_PATHS[i], mode);
		if f ~= nil then
			weeveeDbgHandle = f;
			return
		end
		i = i + 1;
	end
end
function WeeveeDbg(msg)
	local line = tostring(msg);
	if weeveeDbgHandle == nil then
		WeeveeDbgOpen("a");
	end
	if weeveeDbgHandle ~= nil then
		weeveeDbgHandle:write(line);
		weeveeDbgHandle:write("\n");
		weeveeDbgHandle:flush();
	end
end
function WeeveeDbgReset()
	WeeveeDbgOpen("w");
	WeeveeDbg("weevee dbg start");
	TiltedResetLine();
	WeeveeDbgPersist("===== NEW ROLL =====");
end
------------------------------------------------------------------------------
-- Separate, append-only log that survives across multiple map rolls (unlike
-- weevee_dbg.log, which WeeveeDbgReset truncates at the start of every new
-- generation) -- for the water-budget investigation, so results from many
-- rolls in a row accumulate in one place instead of overwriting each other.
local WEEVEE_PERSIST_PATHS = {
	"C:\\Users\\bbruno\\Documents\\My Games\\Sid Meier's Civilization 5\\Logs\\weevee_persist.log",
	"weevee_persist.log",
};
function WeeveeDbgPersist(msg)
	if io == nil or io.open == nil then
		return
	end
	local i = 1;
	while i <= #WEEVEE_PERSIST_PATHS do
		local f = io.open(WEEVEE_PERSIST_PATHS[i], "a");
		if f ~= nil then
			f:write(tostring(msg));
			f:write("\n");
			f:close();
			return
		end
		i = i + 1;
	end
end
function WeeveeDbgCall(name, fn, a1, a2, a3, a4, a5)
	WeeveeDbg("enter " .. name);
	local ok, err = pcall(fn, a1, a2, a3, a4, a5);
	if ok then
		WeeveeDbg("exit " .. name);
	else
		WeeveeDbg("ERR " .. name .. " " .. tostring(err));
	end
end
WeeveeDbg("script loaded 11.0.15");

local OPT_CENTER_SPLIT = 1;
-- Frozen value of the former "Barrier Width" custom option (was the
-- default, index 3 = width 4) now that the option itself has been removed.
local BARRIER_WIDTH_FROZEN_OPS = 3;
-- Frozen value of the former "World Wrap" custom option (was the default,
-- "No") now that the option itself has been removed.
local WORLD_WRAP_FROZEN_OPS = 1;
-- Frozen value of the former "Front Mountain %" custom option (was the
-- default, 25%) now that the option itself has been removed.
local FRONT_MOUNTAIN_DENSITY = 0.25;
-- Per-side mountain budget for the front mountain field (5 columns).
-- Mirrored automatically to the other front. Static for now while the new
-- field design (PlaceFrontMountainField) is being tuned from scratch.
local FRONT_MOUNTAIN_BUDGET = 15;
-- Kept separate from FRONT_MOUNTAIN_BUDGET in case Standard-Diagonal needs
-- to diverge again later (it reads busier at the same budget, since its
-- field traces the fold instead of straight columns).
local FRONT_MOUNTAIN_BUDGET_DIAGONAL = 15;
-- No contiguous mountain blob touching the front ridges may exceed this
-- many tiles, counting merges with mountains from the normal terrain pass.
local FRONT_MOUNTAIN_CLUMP_CAP = 5;
-- Chance a flat tile adjacent to a mountain becomes hills (was a flat 100%).
local FRONT_FOOTHILL_CHANCE = 90;
-- Inverse rule: chance a hill with NO adjacent mountain gets demoted back
-- to flat, thinning out hills that aren't actually next to what made them.
local FRONT_DEHILL_CHANCE = 15;
-- Testing switch: when true, PurgeFrontMountainColumns still runs (clearing
-- tectonics' mountains out of the front's 3-column zone) but
-- PlaceFrontMountainField is skipped, so the purge alone can be judged
-- in-game before the field is layered back on top of a clean slate.
local DISABLE_FRONT_MOUNTAIN_RIDGES = false;
-- Bramble's solid, deterministic jungle ring right at the tundra edge (see
-- BrambleAddJungle). Also used by TongueResourcePlotOk/TongueIsHomePlot to
-- keep resources out of that ring -- stock passes like AddForestToResource
-- can still convert a jungle tile to forest for a resource that needs it,
-- which read as forest patches stabbing into an otherwise solid jungle
-- band; pushing resource candidates past this ring keeps the ring itself
-- clean and only lets that happen further out, in the already-wild part.
local BRAMBLE_JUNGLE_CORE_DEPTH = 3;
-- Every PlaceFrontMountainField call this attempt records its west-side
-- columns/opening here, so AuditFrontMountainGaps (post-wonder, west side
-- only) can re-check rule 3 against the final map -- including Natural
-- Wonders that landed in columns 4-5 after generation already committed to
-- a layout. Always reassigned fresh in GeneratePlotTypes before it's read.
local frontMountainZones = {};
local SPLIT_SNOW = 1;
local SPLIT_SNOW_V2 = 2;
local SPLIT_WETLAND = 3;
local SPLIT_DESERT = 4;
local SPLIT_WASTELAND = 5;
local SPLIT_PEAKS = 6;
local SPLIT_FROSTY = 7;
local SPLIT_TONGUE = 8;
local SPLIT_BRAMBLE = 9;
local SPLIT_RANDOM = 10;
local BARE_MOUNTAIN_TARGET = 20;
local SPLIT_MENU_RANDOM = 1; -- Random's dropdown position
local WRAP_NO = 1;
local WRAP_YES = 2;
local WRAP_RANDOM = 3;
local DEF_WORLD_AGE = 2;
local DEF_TEMPERATURE = 2;
local DEF_RAINFALL = 2;
local DEF_RESOURCES = 4;
local DEF_TEAM = 1;
local DEF_FRONTLINE = 7;
local DEF_BACK = 7;
local DEF_MIRRORED = 1;
local DEF_TOPBOTTOM = 7;
local DEF_NATURAL_WONDERS = 16;
local mireBand = {};
local murkTundraLakeTiles = {};
local peakDist = {};
local peakNX = {};
local peakNY = {};
local peakMassif = {};
local peakHillStyle = {};
local peakHillT1 = {};
local peakHillT2 = {};
local peakHillT3 = {};
local peakForestStyle = {};
local nPeakMassifs = 0;
local riverEdgeList = {};

------------------------------------------------------------------------------
function GetResourceSetting()
	return DEF_RESOURCES;
end
------------------------------------------------------------------------------
function GetMapScriptInfo()
	return {
		Name = "[COLOR_HIGHLIGHT_TEXT] Weevee Map 11.0.15 [ENDCOLOR]",
		Description = "",
		IsAdvancedMap = false,
		SupportsMultiplayer = true,
		IconIndex = 18,
		CustomOptions = {
			{
				Name = "[COLOR_HIGHLIGHT_TEXT]Climate[ENDCOLOR]",
				Values = {
					"[COLOR_HIGHLIGHT_TEXT][ICON_CAPITAL] Random[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Standard[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Standard - Diagonal[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Murky[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Oasis[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Peaky[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Frosty (WIP)[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Bramble (WIP)[ENDCOLOR]",
					"[COLOR_HIGHLIGHT_TEXT]Wasteland (WIP)[ENDCOLOR]",
				},
				DefaultValue = 1,
				SortPriority = -99,
			},
		},
	}
end
------------------------------------------------------------------------------
------------------------------------------------------------------------------
local barrierSplitResolved = false;
local barrierSplit = SPLIT_SNOW;
-- Climate dropdown order (position 1 is always Random, checked separately
-- below): Random, Standard, Standard-Diagonal, Murky, Oasis, Peaky, Frosty,
-- Slate, Wasteland. This maps each dropdown position to the SPLIT_ constant
-- that actually identifies that climate internally -- the two have drifted
-- apart since the constants were numbered for the dropdown's original order.
-- Index 1 (Random) is intentionally left unused; that position is handled
-- before this table is ever consulted.
local CLIMATE_OPS_TO_SPLIT = {
	nil, SPLIT_SNOW_V2, SPLIT_TONGUE, SPLIT_WETLAND, SPLIT_DESERT,
	SPLIT_PEAKS, SPLIT_FROSTY, SPLIT_BRAMBLE, SPLIT_WASTELAND,
};
function ResolveBarrierSplit()
	if barrierSplitResolved then
		return barrierSplit;
	end
	barrierSplitResolved = true;
	local ops = Map.GetCustomOption(OPT_CENTER_SPLIT);
	if ops == SPLIT_MENU_RANDOM or ops == SPLIT_RANDOM then
		local pool = {SPLIT_SNOW_V2, SPLIT_PEAKS, SPLIT_TONGUE, SPLIT_WETLAND, SPLIT_DESERT};
		barrierSplit = pool[Map.Rand(#pool, "Barrier Terrain Random") + 1];
		print("Barrier Terrain random:", barrierSplit);
	else
		barrierSplit = CLIMATE_OPS_TO_SPLIT[ops];
	end
	return barrierSplit;
end
------------------------------------------------------------------------------
local barrierWrapResolved = false;
local barrierWrap = false;
function ResolveWrap()
	if barrierWrapResolved then
		return barrierWrap;
	end
	barrierWrapResolved = true;
	if ResolveBarrierSplit() == SPLIT_SNOW then
		barrierWrap = false;
		print("Barrier wrap: ignored (legacy snow)");
		return barrierWrap;
	end
	local ops = WORLD_WRAP_FROZEN_OPS;
	if ops == WRAP_RANDOM then
		barrierWrap = (Map.Rand(2, "Barrier Wrap Random") == 1);
		print("Barrier wrap random:", barrierWrap);
	else
		barrierWrap = (ops == WRAP_YES);
	end
	return barrierWrap;
end
------------------------------------------------------------------------------
function GetBarrierConfig()
	local ops = ResolveBarrierSplit();
	local wrap = ResolveWrap();
	if ops == SPLIT_SNOW_V2 then
		return {
			kind = "snow",
			wrap = wrap,
			mountainPct = 2,
			hillPct = 24,
			iceLakePermille = 0,
			forestPct = 14,
			oasisPctOfFlat = 0,
			-- Standard's front mountains use their own column-weighted ridge
			-- design (see the front-mountain dispatch below), not the
			-- generic chaotic ridge.
			chaoticMountains = false,
		};
	end
	if ops == SPLIT_DESERT then
		return {
			kind = "desert",
			wrap = wrap,
			mountainPct = 5,
			hillPct = 20,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 5,
			chaoticMountains = true,
		};
	end
	if ops == SPLIT_WASTELAND then
		return {
			kind = "wasteland",
			wrap = wrap,
			mountainPct = 8,
			hillPct = 20,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 0,
			chaoticMountains = true,
			falloutBarrierPct = 30,
			falloutPlayableNearPct = 6,
			falloutPlayableFarPct = 18,
		};
	end
	if ops == SPLIT_WETLAND then
		return {
			kind = "wetland",
			wrap = wrap,
			mountainPct = 8,
			hillPct = 20,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 0,
			-- Murky's front mountains use the column-weighted ridge design
			-- (see the front-mountain dispatch below), not the generic
			-- chaotic ridge, so it gets the narrower default foothill band
			-- to match (see chaoticMountains' other use sites).
			chaoticMountains = false,
			marshBarrierPct = 34,
			jungleBarrierPct = 0,
			forestBarrierPct = 22,
		};
	end
	if ops == SPLIT_PEAKS then
		return {
			kind = "peaks",
			wrap = wrap,
			mountainPct = 8,
			hillPct = 20,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 0,
			chaoticMountains = false,
		};
	end
	if ops == SPLIT_FROSTY then
		return {
			kind = "frosty",
			wrap = wrap,
			mountainPct = 2,
			hillPct = 19,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 0,
			chaoticMountains = true,
		};
	end
	if ops == SPLIT_TONGUE then
		return {
			kind = "snow",
			wrap = wrap,
			mountainPct = 2,
			hillPct = 24,
			iceLakePermille = 0,
			forestPct = 14,
			oasisPctOfFlat = 0,
			chaoticMountains = false,
			tilted = true,
		};
	end
	if ops == SPLIT_BRAMBLE then
		return {
			kind = "bramble",
			wrap = wrap,
			-- Mountains, hills and water for Bramble are entirely hand-placed
			-- (AddBrambleLayout/AddBrambleFeatures) rather than rolled from
			-- these percentages -- zeroed here for self-documentation, not
			-- functionally load-bearing (Bramble is excluded from the generic
			-- barrier-percentage painter the same way Slate/Snaky was).
			mountainPct = 0,
			hillPct = 0,
			iceLakePermille = 0,
			forestPct = 0,
			oasisPctOfFlat = 0,
			chaoticMountains = true,
		};
	end
	return nil;
end
------------------------------------------------------------------------------
function BarrierTerrainType(cfg)
	if cfg.kind == "desert" then
		return TerrainTypes.TERRAIN_DESERT;
	end
	if cfg.kind == "wasteland" then
		return TerrainTypes.TERRAIN_TUNDRA;
	end
	if cfg.kind == "wetland" then
		return TerrainTypes.TERRAIN_GRASS;
	end
	if cfg.kind == "peaks" then
		return TerrainTypes.TERRAIN_PLAINS;
	end
	if cfg.kind == "frosty" then
		return TerrainTypes.TERRAIN_TUNDRA;
	end
	if cfg.kind == "tongue" or cfg.kind == "bramble" then
		return TerrainTypes.TERRAIN_TUNDRA;
	end
	return TerrainTypes.TERRAIN_SNOW;
end
------------------------------------------------------------------------------
function BarrierTransitionType(cfg)
	if cfg.kind == "wasteland" then
		return TerrainTypes.TERRAIN_DESERT;
	end
	if cfg.kind == "wetland" then
		return TerrainTypes.TERRAIN_DESERT;
	end
	if cfg.kind == "frosty" then
		return TerrainTypes.TERRAIN_DESERT;
	end
	if cfg.kind == "tongue" or cfg.kind == "bramble" then
		return TerrainTypes.TERRAIN_TUNDRA;
	end
	return TerrainTypes.TERRAIN_TUNDRA;
end
------------------------------------------------------------------------------
function IsSnowWrapX()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.wrap == true;
end
------------------------------------------------------------------------------
function IsSnowNoWrap()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.wrap == false;
end
------------------------------------------------------------------------------
function IsExploBalance()
	return true
end
------------------------------------------------------------------------------
function UsesExploCoastShape()
	if IsExploBalance() then
		return true
	end
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.kind == "frosty" and IsSnowNoWrap();
end
------------------------------------------------------------------------------
local saltPlanResolved = false;
local saltCutPct = 0;
local saltNSeas = 0;
local saltSeaSizeMin = 3;
local saltSeaSizeRand = 8;
local saltAllowEdge = false;
function ResolveSaltWaterPlan()
	if saltPlanResolved then
		return saltCutPct, saltNSeas, saltSeaSizeMin, saltSeaSizeRand, saltAllowEdge;
	end
	saltPlanResolved = true;
	if UsesExploCoastShape() then
		local cfg = GetBarrierConfig();
		if cfg ~= nil and cfg.kind == "frosty" then
			saltCutPct = 30;
			saltNSeas = 1 + Map.Rand(2, "Frosty Inland Seas");
		elseif cfg ~= nil and cfg.kind == "peaks" then
			-- Inland seas were never actually carved as a distinct feature
			-- for this climate -- nothing downstream consumes saltNSeas here,
			-- it's cutPct alone that decides how much of the back coast's
			-- vertical extent becomes real water vs. forced flat land (see
			-- ShapeNoWrapBackstrip). A 50/50 roll used to sacrifice up to half
			-- that budget to a "sea" that was never drawn, for nothing.
			-- Pinning cutPct here (and anchoring the kept window to a north
			-- or south corner in ShapeNoWrapBackstrip, rather than letting it
			-- float anywhere) reallocates the salt-water budget into one
			-- compact corner blob instead of a long thin stretch the full
			-- height of the back coast -- room for one proper peak-island
			-- plus a handful of splinters, not a scatter of tiny islets
			-- stretched the whole way up the map. 35-50% (rather than the
			-- original 60-75%) roughly triples the blob's surface area
			-- together with the widened column depth below, while still
			-- varying per roll instead of pinning one fixed size/shape.
			saltCutPct = 35 + Map.Rand(16, "Peaks BackCoast Cut");
			saltNSeas = 0;
		elseif Map.Rand(2, "Explo back coast plan") == 0 then
			saltCutPct = 50;
			saltNSeas = 2;
		else
			saltCutPct = 25;
			saltNSeas = 1;
		end
	else
		local cfg = GetBarrierConfig();
		if cfg ~= nil and cfg.kind == "frosty" then
			saltNSeas = 1 + Map.Rand(2, "Frosty Inland Seas");
		else
			saltNSeas = Map.Rand(4, "Snow Wrap Lake Count");
		end
	end
	print("Salt plan: cut", saltCutPct, "% back coast, seas", saltNSeas);
	return saltCutPct, saltNSeas, saltSeaSizeMin, saltSeaSizeRand, saltAllowEdge;
end
------------------------------------------------------------------------------
function ResolveExploBackCoastPlan()
	local cutPct, nSeas = ResolveSaltWaterPlan();
	return cutPct, nSeas;
end
------------------------------------------------------------------------------
function IsOldSnow()
	return ResolveBarrierSplit() == SPLIT_SNOW;
end
------------------------------------------------------------------------------
function IsSnowBarrier()
	return GetBarrierConfig() ~= nil;
end
------------------------------------------------------------------------------
function IsStandardClimate()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.kind == "snow";
end
------------------------------------------------------------------------------
function IsOasisClimate()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.kind == "desert";
end
------------------------------------------------------------------------------
-- Desert (Oasis), Peaks and Wetland all pin fSnowLatitude/fTundraLatitude
-- past 1.0 in GenerateTerrain, disabling vanilla's own latitude-based
-- Tundra/Snow entirely -- their interior is never meant to have any (Oasis
-- has none at all; Peaks and Wetland are grass/plains/mountain climates
-- with none either). EnsureRegionalLuxuryTarget's terraform-rescue tier
-- (tryTerraformOnPlot) doesn't know that -- left unchecked, it will happily
-- carve Tundra/Snow into their interior land anyway to legalize an
-- otherwise-unplaceable regional luxury (e.g. Fur assigned, however rarely,
-- to a region that structurally has no eligible terrain for it at all).
-- Frosty/Standard/Tongue/Bramble/Wasteland are exempt: they're snow/tundra
-- climates themselves, or use Tundra deliberately elsewhere (barrier
-- terrain/transition), so forcing it into their interior isn't a violation.
function ClimateAllowsInteriorPolarTerrain()
	local cfg = GetBarrierConfig();
	if cfg == nil then
		return true
	end
	return cfg.kind ~= "desert" and cfg.kind ~= "peaks" and cfg.kind ~= "wetland";
end
------------------------------------------------------------------------------
function OasisNonDesertLandAdj(x, y)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil
			and adj:IsWater() == false
			and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
			and adj:GetTerrainType() ~= TerrainTypes.TERRAIN_DESERT then
			n = n + 1;
		end
		d = d + 1;
	end
	return n
end
------------------------------------------------------------------------------
function OasisLuxuryWithin(x, y, maxD)
	if maxD == nil or maxD < 1 then
		maxD = 1
	end
	local dy = y - maxD
	while dy <= y + maxD do
		local dx = x - maxD
		while dx <= x + maxD do
			if Map.PlotDistance(x, y, dx, dy) <= maxD then
				local p = Map.GetPlot(dx, dy)
				if p ~= nil and IsWeeveeLuxuryID(p:GetResourceType(-1)) then
					return true
				end
			end
			dx = dx + 1
		end
		dy = dy + 1
	end
	return false
end
------------------------------------------------------------------------------
function OasisWestDesertColumns()
	return 8;
end
------------------------------------------------------------------------------
function OasisIsWestHinterlandX(x, iW)
	if IsOasisClimate() == false or x == nil then
		return false
	end
	if iW == nil then
		iW = Map.GetGridSize();
	end
	local band = OasisWestDesertColumns();
	local mid = math.floor(iW / 2);
	if x < 0 or x >= band then
		return false
	end
	if DEF_MIRRORED == 1 and x > mid then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function OasisHinterlandHarshness(x)
	local band = OasisWestDesertColumns();
	if band <= 1 then
		return 1
	end
	if x <= 0 then
		return 1
	end
	if x >= band then
		return 0
	end
	return (band - 1 - x) / (band - 1);
end
------------------------------------------------------------------------------
function OasisInJunglePocket(x, y)
	local plot = Map.GetPlot(x, y);
	if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
		return true
	end
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil and adj:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
			return true
		end
		d = d + 1;
	end
	return false
end
------------------------------------------------------------------------------
local oasisJungleCached = false;
local oasisJungleExists = false;
function OasisJungleExists()
	if oasisJungleCached then
		return oasisJungleExists
	end
	oasisJungleCached = true;
	oasisJungleExists = false;
	local iW, iH = Map.GetGridSize();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
				oasisJungleExists = true;
				return true
			end
			x = x + 1;
		end
		y = y + 1;
	end
	return false
end
------------------------------------------------------------------------------
function IsTiltedMirrorAxis()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and (cfg.tilted == true or cfg.kind == "bramble");
end
------------------------------------------------------------------------------
function IsBramble()
	local cfg = GetBarrierConfig();
	return cfg ~= nil and cfg.kind == "bramble";
end
------------------------------------------------------------------------------
local tiltedLineReady = false;
local tiltedS0 = 0;
local tiltedShiftReady = false;
local tiltedShiftEven = 0;
local tiltedShiftOdd = 0;
local tongueJungleDepth = nil;
-- Bramble's separator shape: brambleLo[y]/brambleHi[y] are the inclusive
-- tundra column range at row y, covering every row 0..iH-1. Built once per
-- attempt by BrambleEnsureShape (see there for the generation algorithm).
local brambleShapeReady = false;
local brambleLo = {};
local brambleHi = {};
local tongueEconFrac = nil;
local tongueEconFrac2 = nil;
function TiltedResetLine()
	tiltedLineReady = false;
	tiltedShiftReady = false;
	tongueJungleDepth = nil;
	brambleShapeReady = false;
	brambleLo = {};
	brambleHi = {};
	tongueEconFrac = nil;
	tongueEconFrac2 = nil;
	saltPlanResolved = false;
end
------------------------------------------------------------------------------
function TiltedCubeS(col, row)
	local q = col - math.floor(row / 2);
	return 0 - q - row;
end
------------------------------------------------------------------------------
function TiltedEnsureLine()
	if tiltedLineReady then
		return
	end
	local iW, iH = Map.GetGridSize();
	local cx = math.floor((iW - 1) / 2);
	local cy = math.floor((iH - 1) / 2);
	tiltedS0 = TiltedCubeS(cx, cy);
	tiltedLineReady = true;
end
------------------------------------------------------------------------------
-- Reset to Standard-Diagonal's own stable linear fold (2026-09-18) -- the
-- noisy/bulge-pinch shapes kept reading as "off" no matter how they were
-- tuned. This computes the exact same diagonal (TiltedCubeS/tiltedS0, plus
-- the same antisymmetry shift correction TiltedFoldMid uses for
-- Standard-Diagonal) at a fixed width -- a plain, stable diagonal strip.
-- Distortion (noise on top of this) is a deliberate later step, not
-- attempted yet.
--
-- Computed locally rather than by calling TiltedFoldMid/TiltedEnsureShift
-- directly: those go through TiltedSignedDist, which for Bramble
-- dispatches straight back to BrambleSignedDist/BrambleEnsureShape --
-- calling them from inside here would recurse. TiltedCubeS and
-- TiltedEnsureLine are the plain, non-dispatching helpers underneath that
-- formula, safe to call directly.
function BrambleEnsureShape()
	if brambleShapeReady then
		return
	end
	brambleShapeReady = true;
	local iW, iH = Map.GetGridSize();
	TiltedEnsureLine();
	local function rawDiag(x, y)
		return TiltedCubeS(x, y) - tiltedS0;
	end
	local function constantFor(y0)
		local mx = iW - 1;
		local my = iH - 1 - y0;
		return rawDiag(0, y0) + rawDiag(mx, my);
	end
	local shiftEven = (1 - constantFor(0)) / 2;
	local shiftOdd = (1 - constantFor(1)) / 2;
	local halfWidth = 2; -- total width 4, fixed and stable for now
	local y = 0;
	while y < iH do
		local raw = math.floor(y / 2) - y - tiltedS0;
		local shift = shiftEven;
		if y % 2 ~= 0 then
			shift = shiftOdd;
		end
		local center = math.floor(raw + shift + 0.5);
		local lo = center - halfWidth;
		local hi = lo + halfWidth * 2 - 1;
		if lo < 1 then
			local s = 1 - lo;
			lo = lo + s;
			hi = hi + s;
		end
		if hi > iW - 2 then
			local s = hi - (iW - 2);
			lo = lo - s;
			hi = hi - s;
		end
		brambleLo[y] = lo;
		brambleHi[y] = hi;
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Row-local center column of Bramble's separator (see BrambleEnsureShape).
function BrambleFoldMid(y)
	BrambleEnsureShape();
	return math.floor((brambleLo[y] + brambleHi[y]) / 2 + 0.5);
end
------------------------------------------------------------------------------
-- West/east side test for Bramble, in the same >0-means-west convention as
-- TiltedSignedDist -- exactly antisymmetric under the 180-degree mirror by
-- construction (BrambleFoldMid(iH-1-y) == iW-1-BrambleFoldMid(y) follows
-- directly from how the derived rows are built), no shift correction needed.
function BrambleSignedDist(x, y)
	return BrambleFoldMid(y) - x;
end
------------------------------------------------------------------------------
function TiltedSignedDist(x, y)
	if IsBramble() then
		return BrambleSignedDist(x, y);
	end
	TiltedEnsureLine();
	return TiltedCubeS(x, y) - tiltedS0;
end
------------------------------------------------------------------------------
-- The hex offset->cube conversion isn't exactly antisymmetric under the
-- engine's 180-degree mirror copy: TiltedSignedDist(x,y) + TiltedSignedDist(mirror(x,y))
-- is a constant, not 0 -- and that constant differs by row parity. A barrier
-- band centered on plain TiltedSignedDist==0 therefore doesn't line up with
-- itself after mirroring (the copy lands a few columns off, widening/streaking
-- the band). Centering the band on that constant instead fixes it exactly.
function TiltedEnsureShift()
	if tiltedShiftReady then
		return
	end
	tiltedShiftReady = true;
	TiltedEnsureLine();
	local iW, iH = Map.GetGridSize();
	local function constantFor(y0)
		local mx = iW - 1;
		local my = iH - 1 - y0;
		return TiltedSignedDist(0, y0) + TiltedSignedDist(mx, my);
	end
	tiltedShiftEven = (1 - constantFor(0)) / 2;
	tiltedShiftOdd = (1 - constantFor(1)) / 2;
end
------------------------------------------------------------------------------
-- Row-local equivalent of the constant `mid` column, for climates whose
-- separator runs along the tilted fold instead of a straight vertical line.
-- Mirror-consistent column for this row (see TiltedEnsureShift) -- a window
-- centered here stays the same width after the engine's mirror copy.
function TiltedFoldMid(y)
	if IsBramble() then
		return BrambleFoldMid(y);
	end
	TiltedEnsureLine();
	TiltedEnsureShift();
	local raw = math.floor(y / 2) - y - tiltedS0;
	local shift = tiltedShiftEven;
	if y % 2 ~= 0 then
		shift = tiltedShiftOdd;
	end
	-- On a map height divisible by 4 (see GetMapInitData) this shift always
	-- lands on a whole number -- exact-width and visually straight at once.
	-- (On other heights it can land on a half-integer instead, which has no
	-- rounding that's both; see the Standard-Diagonal width/smoothness notes.)
	return math.floor(raw + shift + 0.5);
end
------------------------------------------------------------------------------
function TiltedFoldWest(x, y)
	if DEF_MIRRORED ~= 1 then
		return x, y
	end
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	if x < mid then
		return x, y
	end
	return iW - x - 1, iH - y - 1;
end
------------------------------------------------------------------------------
function MirrorOwnsPlot(x, y, mirrored, iW)
	if mirrored ~= true then
		return true
	end
	if x <= iW * 0.5 then
		return true
	end
	if IsTiltedMirrorAxis() == false then
		return false
	end
	return TiltedSignedDist(x, y) > 0
end
------------------------------------------------------------------------------
function TongueNoGoWidth()
	local wrapN, centerN = ResolveSnowWrapWidths();
	if centerN < 1 then
		return 1
	end
	return centerN;
end
------------------------------------------------------------------------------
function TongueHillDist()
	return 1
end
------------------------------------------------------------------------------
function TongueMtnDist()
	return 2
end
------------------------------------------------------------------------------
function TongueGetJungleDepth()
	if tongueJungleDepth == nil then
		tongueJungleDepth = 2 + Map.Rand(3, "Tongue Jungle Depth");
	end
	return tongueJungleDepth;
end
------------------------------------------------------------------------------
-- Bramble note (2026-09-17): these two used to reject any TERRAIN_TUNDRA
-- tile as a belt-and-suspenders catch for the separator strip itself (which
-- was always tundra terrain). Since the corner-flavor smear now also paints
-- real tundra out in the econ zone, that blanket terrain check started
-- rejecting those tiles from every resource/luxury/home-plot list too --
-- correctly excluding the actual strip via brambleLo/brambleHi membership
-- instead fixes that without losing the original protection.
function TongueIsHomePlot(x, y)
	if IsBramble() == false then
		return true
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil or plot:IsWater() then
		return false
	end
	if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	if x >= brambleLo[y] and x <= brambleHi[y] then
		return false
	end
	if TiltedSignedDist(x, y) <= 0 then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function TongueResourcePlotOk(x, y)
	if IsBramble() == false then
		return true
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil then
		return false
	end
	-- Excludes the solid jungle core too (BRAMBLE_JUNGLE_CORE_DEPTH), not
	-- just the tundra strip itself -- see that constant's comment.
	if x >= brambleLo[y] - BRAMBLE_JUNGLE_CORE_DEPTH and x <= brambleHi[y] + BRAMBLE_JUNGLE_CORE_DEPTH then
		return false
	end
	if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	if TiltedSignedDist(x, y) <= 0 then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function FilterPlotIndexListToTongueHome(list, iW)
	if IsBramble() == false or list == nil then
		return list
	end
	local out = {};
	local k = 1;
	while k <= #list do
		local i = list[k];
		local x = (i - 1) % iW;
		local y = math.floor((i - 1) / iW);
		if TongueResourcePlotOk(x, y) then
			table.insert(out, i);
		end
		k = k + 1;
	end
	return out
end
------------------------------------------------------------------------------
function FilterTongueHomeLuxuryLists(lists)
	if IsBramble() == false or lists == nil then
		return lists
	end
	local iW = Map.GetGridSize();
	local n = 1;
	while n <= 15 do
		if lists[n] == nil then
			lists[n] = {};
		else
			lists[n] = FilterPlotIndexListToTongueHome(lists[n], iW);
		end
		n = n + 1;
	end
	return lists
end
------------------------------------------------------------------------------
function FilterTongueHomeResourceLists(self)
	if IsBramble() == false then
		return
	end
	local iW = Map.GetGridSize();
	local names = {
		"coast_next_to_land_list", "marsh_list", "flood_plains_list",
		"hills_open_list", "hills_covered_list", "hills_jungle_list", "hills_forest_list",
		"jungle_flat_list", "forest_flat_list", "desert_flat_no_feature",
		"plains_flat_no_feature", "dry_grass_flat_no_feature", "fresh_water_grass_flat_no_feature",
		"tundra_flat_including_forests", "forest_flat_that_are_not_tundra",
		"grass_flat_no_feature", "tundra_flat_no_feature", "snow_flat_list",
		"hills_list", "land_list", "coast_list", "front_coast_list",
		"marble_list", "extra_deer_list", "desert_wheat_list", "banana_list"
	};
	local n = 1;
	while names[n] ~= nil do
		local key = names[n];
		self[key] = FilterPlotIndexListToTongueHome(self[key], iW);
		n = n + 1;
	end
	self.global_luxury_plot_lists = {
		self.coast_next_to_land_list,
		self.marsh_list,
		self.flood_plains_list,
		self.hills_open_list,
		self.hills_covered_list,
		self.hills_jungle_list,
		self.hills_forest_list,
		self.jungle_flat_list,
		self.forest_flat_list,
		self.desert_flat_no_feature,
		self.plains_flat_no_feature,
		self.dry_grass_flat_no_feature,
		self.fresh_water_grass_flat_no_feature,
		self.tundra_flat_including_forests,
		self.forest_flat_that_are_not_tundra,
	};
end
------------------------------------------------------------------------------
function TongueIsBarrierPlot(x, y)
	if IsBramble() == false then
		return false
	end
	return TongueIsHomePlot(x, y) == false
end
------------------------------------------------------------------------------
function PlotRejectsNaturalWonder(x, y)
	if IsTiltedMirrorAxis() == false then
		return false
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil then
		return true
	end
	if IsBramble() and x >= brambleLo[y] and x <= brambleHi[y] then
		return true
	end
	if TiltedSignedDist(x, y) <= 0 then
		-- Applies to every tilted-mirror-axis climate (Standard-Diagonal
		-- and Bramble), not just one of them: without this, vanilla's
		-- PlaceNaturalWonders (which scans the whole canvas, unaware of the
		-- west/east split) is free to independently place wonders on the
		-- not-yet-generated "away" half as well as the real west half. Those
		-- get caught by the final mirror pass everywhere the mirror
		-- destination isn't skipped, but wherever it is skipped (right along
		-- the wandering diagonal fold), the independently-placed wonder
		-- survives -- doubling the total count, and occasionally landing
		-- right next to a real wonder across the fold since the two "halves"
		-- are geometric neighbors there.
		return true
	end
	return false
end
------------------------------------------------------------------------------
function TongueStartTooClose(x, y)
	if IsBramble() then
		if TongueIsHomePlot(x, y) == false then
			return true
		end
		local iH = select(2, Map.GetGridSize());
		local yy = y - 3;
		while yy <= y + 3 do
			if yy >= 0 and yy < iH then
				local xx = x - 3;
				while xx <= x + 3 do
					if Map.PlotDistance(x, y, xx, yy) <= 3 and xx >= brambleLo[yy] and xx <= brambleHi[yy] then
						return true
					end
					xx = xx + 1;
				end
			end
			yy = yy + 1;
		end
		return false
	end
	if IsTiltedMirrorAxis() == false then
		return false
	end
	-- Standard-Diagonal: the barrier band wanders with the fold from row to
	-- row, so "distance to the front" has to be measured from this row's own
	-- local band instead of a fixed column -- otherwise a start could land
	-- right against the barrier on rows where it has swung close by.
	local _, centerN = ResolveSnowWrapWidths();
	local half = centerN / 2;
	local mid = TiltedFoldMid(y);
	local frontBuffer = 5; -- matches the minimum-distance convention used elsewhere (NudgePlayerStartsMinDist, EnforceMinStartDistance, wonder ripple)
	if x >= mid - half - frontBuffer and x <= mid + half - 1 + frontBuffer then
		return true
	end
	return false
end
------------------------------------------------------------------------------
function TiltedSkipMirrorDest(sx, sy, dx, dy)
	if IsTiltedMirrorAxis() == false then
		return false
	end
	local iW, iH = Map.GetGridSize();
	if dy >= iH * 0.5 then
		return false
	end
	if TiltedSignedDist(dx, dy) > 0 and TiltedSignedDist(sx, sy) <= 0 then
		return true
	end
	return false
end
------------------------------------------------------------------------------
function TiltedCopyHomePastMidToPair(copyRes)
	if DEF_MIRRORED ~= 1 then
		return
	end
	if IsTiltedMirrorAxis() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local y = 0;
	while y < iH do
		local x = mid;
		while x < iW do
			if TiltedSignedDist(x, y) > 0 then
				local plot = Map.GetPlot(x, y);
				local mx = iW - x - 1;
				local my = iH - y - 1;
				local mp = Map.GetPlot(mx, my);
				if plot ~= nil and mp ~= nil then
					mp:SetPlotType(plot:GetPlotType(), false, false);
					mp:SetTerrainType(plot:GetTerrainType(), false, false);
					mp:SetFeatureType(plot:GetFeatureType(), -1);
					if copyRes == true then
						mp:SetResourceType(plot:GetResourceType(-1), plot:GetNumResource());
						mp:SetImprovementType(plot:GetImprovementType());
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function CopyWestToEast()
	if DEF_MIRRORED ~= 1 then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local x = 0;
	while x < mid do
		local y = 0;
		while y < iH do
			local mx = iW - x - 1;
			local my = iH - y - 1;
			if TiltedSkipMirrorDest(x, y, mx, my) == false then
				local plot = Map.GetPlot(x, y);
				local mp = Map.GetPlot(mx, my);
				if plot ~= nil and mp ~= nil then
					mp:SetPlotType(plot:GetPlotType(), false, false);
					mp:SetTerrainType(plot:GetTerrainType(), false, false);
					mp:SetFeatureType(plot:GetFeatureType(), -1);
				end
			end
			y = y + 1;
		end
		x = x + 1;
	end
	TiltedCopyHomePastMidToPair(false);
end
------------------------------------------------------------------------------
function GetSungodLuxuryIDs(asp)
	local ids = {};
	if asp.citrus_ID ~= nil then
		table.insert(ids, asp.citrus_ID);
	end
	if asp.cocoa_ID ~= nil then
		table.insert(ids, asp.cocoa_ID);
	end
	if asp.olives_ID ~= nil then
		table.insert(ids, asp.olives_ID);
	end
	local coconutID = GameInfoTypes["RESOURCE_COCONUT"];
	if coconutID ~= nil then
		table.insert(ids, coconutID);
	end
	return ids;
end
------------------------------------------------------------------------------
function IsSungodLuxuryID(asp, resID)
	if resID == nil then
		return false
	end
	local ids = GetSungodLuxuryIDs(asp);
	local i = 1;
	while i <= #ids do
		if ids[i] == resID then
			return true
		end
		i = i + 1;
	end
	return false
end
------------------------------------------------------------------------------
function WestHasSungodRegional(asp)
	local iW = Map.GetGridSize();
	local mid = iW * 0.5;
	local r = 1;
	while r <= asp.iNumCivs do
		local res = asp.region_luxury_assignment[r];
		if IsSungodLuxuryID(asp, res) then
			local start = asp.startingPlots[r];
			if start ~= nil and start[1] < mid then
				return true
			end
		end
		r = r + 1;
	end
	return false
end
------------------------------------------------------------------------------
function ApplyWastelandLuxuryWeights(self)
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local tundra = {};
	local function add(id, w)
		if id ~= nil then
			table.insert(tundra, {id, w});
		end
	end
	add(self.fur_ID, 40);
	add(self.silver_ID, 40);
	add(self.amber_ID, 40);
	add(self.salt_ID, 40);
	add(self.gold_ID, 40);
	add(self.copper_ID, 40);
	add(self.gems_ID, 40);
	add(self.jade_ID, 40);
	add(self.lapis_ID, 40);
	add(self.whale_ID, 16);
	add(self.crab_ID, 16);
	self.luxury_region_weights[1] = tundra;
	local t = 2;
	while t <= 8 do
		local list = self.luxury_region_weights[t];
		if list ~= nil then
			if self.whale_ID ~= nil then
				table.insert(list, {self.whale_ID, 16});
			end
			if self.crab_ID ~= nil then
				table.insert(list, {self.crab_ID, 16});
			end
		end
		t = t + 1;
	end
end
------------------------------------------------------------------------------
function ApplyTongueLuxuryWeights(self)
	local cfg = GetBarrierConfig();
	if cfg == nil or (cfg.kind ~= "tongue" and cfg.kind ~= "bramble") then
		return
	end
	local jungle = {};
	local function add(id, w)
		if id ~= nil then
			table.insert(jungle, {id, w});
		end
	end
	add(self.cocoa_ID, 40);
	add(self.citrus_ID, 40);
	add(self.spices_ID, 30);
	add(self.dye_ID, 30);
	add(self.gems_ID, 25);
	add(self.ivory_ID, 20);
	add(self.silk_ID, 15);
	if self.luxury_region_weights[2] ~= nil then
		self.luxury_region_weights[2] = jungle;
	end
	print("Tongue luxury weights: jungle regions only");
end
------------------------------------------------------------------------------
function ApplyLiberalCoastalLuxuryWeights(self)
	return
end
------------------------------------------------------------------------------
local DetermineRegionTypesVanilla = AssignStartingPlots.DetermineRegionTypes;
function AssignStartingPlots:DetermineRegionTypes()
	DetermineRegionTypesVanilla(self);
	if IsBramble() == false then
		return
	end
	local r = 1;
	while self.regionTypes[r] ~= nil do
		if self.regionTypes[r] == 1 then
			local c = self.regionTerrainCounts[r];
			local j = 0;
			local f = 0;
			local p = 0;
			if c ~= nil then
				if c[17] ~= nil then
					j = c[17];
				end
				if c[16] ~= nil then
					f = c[16];
				end
				if c[12] ~= nil then
					p = c[12];
				end
			end
			if j >= f and j >= p then
				self.regionTypes[r] = 2;
			elseif f >= p then
				self.regionTypes[r] = 3;
			else
				self.regionTypes[r] = 6;
			end
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
local InitLuxuryWeightsVanilla = AssignStartingPlots.__InitLuxuryWeights;
function AssignStartingPlots:__InitLuxuryWeights()
	InitLuxuryWeightsVanilla(self);
	ApplyWastelandLuxuryWeights(self);
	ApplyTongueLuxuryWeights(self);
	ApplyLiberalCoastalLuxuryWeights(self);
end
------------------------------------------------------------------------------
local AssignLuxuryToRegionVanilla = AssignStartingPlots.AssignLuxuryToRegion;
function AssignStartingPlots:AssignLuxuryToRegion(region_number)
	local cfg = GetBarrierConfig();
	local savedCoast = nil;
	if cfg ~= nil and cfg.kind == "wasteland" then
		if self.startLocationConditions[region_number] ~= nil and self.startLocationConditions[region_number][1] == true then
			if self.regionTerrainCounts[region_number] ~= nil then
				savedCoast = self.regionTerrainCounts[region_number][8];
				if savedCoast == nil or savedCoast < 90 then
					self.regionTerrainCounts[region_number][8] = 90;
				else
					savedCoast = nil;
				end
			end
		end
	end
	local use_this_ID;
	if cfg == nil or (cfg.kind ~= "desert" or WestHasSungodRegional(self) == false) then
		use_this_ID = AssignLuxuryToRegionVanilla(self, region_number);
	else
		local sungod = GetSungodLuxuryIDs(self);
		local saved = {};
		local i = 1;
		while i <= #sungod do
			local id = sungod[i];
			saved[id] = self.luxury_assignment_count[id];
			if saved[id] == nil then
				saved[id] = 0;
			end
			self.luxury_assignment_count[id] = 3;
			i = i + 1;
		end
		use_this_ID = AssignLuxuryToRegionVanilla(self, region_number);
		i = 1;
		while i <= #sungod do
			local id = sungod[i];
			self.luxury_assignment_count[id] = saved[id];
			i = i + 1;
		end
		print("Sungod regional cap: blocked extra citrus/cocoa/olives/coconut for region", region_number);
	end
	if savedCoast ~= nil then
		self.regionTerrainCounts[region_number][8] = savedCoast;
	end
	if use_this_ID == nil
		or use_this_ID == self.banana_ID
		or use_this_ID == self.wheat_ID
		or use_this_ID == self.cow_ID
		or use_this_ID == self.deer_ID
		or use_this_ID == self.sheep_ID
		or use_this_ID == self.fish_ID
		or use_this_ID == self.stone_ID
		or use_this_ID == self.maize_ID
		or use_this_ID == self.hardwood_ID then
		use_this_ID = self.gold_ID;
		if use_this_ID == nil then
			use_this_ID = self.silver_ID;
		end
	end
	return use_this_ID;
end
------------------------------------------------------------------------------
local GetIndicesForLuxuryTypeVanilla = AssignStartingPlots.GetIndicesForLuxuryType;
function AssignStartingPlots:GetIndicesForLuxuryType(resource_ID)
	if resource_ID == nil then
		return 4, 10, 5, 11;
	end
	local p, s, t, q = GetIndicesForLuxuryTypeVanilla(self, resource_ID);
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return p, s, t, q;
	end
	if resource_ID == self.gems_ID then
		return 7, 4, 14, 5;
	end
	if resource_ID == self.gold_ID
		or resource_ID == self.jade_ID
		or resource_ID == self.lapis_ID
		or resource_ID == self.amber_ID
		or resource_ID == self.copper_ID then
		if p ~= 14 and s ~= 14 and t ~= 14 and q ~= 14 then
			if q == nil or q < 1 then
				q = 14;
			elseif t == nil or t < 1 then
				t = 14;
			else
				q = 14;
			end
		end
	end
	return p, s, t, q;
end
------------------------------------------------------------------------------
local GetRegionLuxuryTargetNumbersVanilla = AssignStartingPlots.GetRegionLuxuryTargetNumbers;
function AssignStartingPlots:GetRegionLuxuryTargetNumbers()
	return GetRegionLuxuryTargetNumbersVanilla(self);
end
------------------------------------------------------------------------------
function WastelandCoastalLuxuryIDs(asp)
	local ids = {};
	if asp.whale_ID ~= nil then
		table.insert(ids, asp.whale_ID);
	end
	if asp.pearls_ID ~= nil then
		table.insert(ids, asp.pearls_ID);
	end
	if asp.crab_ID ~= nil then
		table.insert(ids, asp.crab_ID);
	end
	if asp.coral_ID ~= nil then
		table.insert(ids, asp.coral_ID);
	end
	return ids;
end
------------------------------------------------------------------------------
function TableRemoveValue(t, id)
	local i = 1;
	while i <= #t do
		if t[i] == id then
			table.remove(t, i);
			return true
		end
		i = i + 1;
	end
	return false
end
------------------------------------------------------------------------------
function ForceCoastalLuxuryRoles(asp)
	if asp == nil then
		return
	end
	local coastal = WastelandCoastalLuxuryIDs(asp);
	if #coastal < 1 then
		return
	end
	local shuffled = GetShuffledCopyOfTable(coastal);
	local need = 2 + Map.Rand(2, "Coastal lux types");
	if need > #shuffled then
		need = #shuffled;
	end
	local picked = {};
	local i = 1;
	while i <= #shuffled do
		local id = shuffled[i];
		if TestMembership(asp.resourceIDs_assigned_to_regions, id) or TestMembership(asp.resourceIDs_assigned_to_cs, id) then
			table.insert(picked, id);
		end
		i = i + 1;
	end
	i = 1;
	while i <= #shuffled and #picked < need do
		local id = shuffled[i];
		if TestMembership(picked, id) == false then
			table.insert(picked, id);
			if TestMembership(asp.resourceIDs_assigned_to_random, id) == false then
				TableRemoveValue(asp.resourceIDs_not_being_used, id);
				table.insert(asp.resourceIDs_assigned_to_random, id);
				asp.iNumTypesRandom = asp.iNumTypesRandom + 1;
				if asp.iNumTypesDisabled > 0 then
					asp.iNumTypesDisabled = asp.iNumTypesDisabled - 1;
				end
			end
		end
		i = i + 1;
	end
	i = 1;
	while i <= #shuffled do
		local id = shuffled[i];
		if TestMembership(picked, id) == false
			and TestMembership(asp.resourceIDs_assigned_to_regions, id) == false
			and TestMembership(asp.resourceIDs_assigned_to_cs, id) == false then
			if TableRemoveValue(asp.resourceIDs_assigned_to_random, id) then
				table.insert(asp.resourceIDs_not_being_used, id);
				if asp.iNumTypesRandom > 0 then
					asp.iNumTypesRandom = asp.iNumTypesRandom - 1;
				end
				asp.iNumTypesDisabled = asp.iNumTypesDisabled + 1;
			end
		end
		i = i + 1;
	end
	asp.forcedCoastalLux = picked;
	asp.wastelandForcedCoastalLux = picked;
	print("Forced coastal lux types:", #picked);
end
------------------------------------------------------------------------------
function WastelandForceCoastalLuxuryRoles(asp)
	ForceCoastalLuxuryRoles(asp);
end
------------------------------------------------------------------------------
function EnsureCoastalLuxCanAppear(asp)
	if asp == nil or IsStandardClimate() then
		return
	end
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "wasteland" then
		return
	end
	local coastal = WastelandCoastalLuxuryIDs(asp);
	local already = 0;
	local i = 1;
	while i <= #coastal do
		local id = coastal[i];
		if TestMembership(asp.resourceIDs_assigned_to_regions, id) or TestMembership(asp.resourceIDs_assigned_to_cs, id) or TestMembership(asp.resourceIDs_assigned_to_random, id) then
			already = already + 1;
		end
		i = i + 1;
	end
	local want = #coastal;
	if IsOasisClimate() then
		want = 2;
	end
	coastal = GetShuffledCopyOfTable(coastal);
	i = 1;
	while i <= #coastal and already < want do
		local id = coastal[i];
		if TableRemoveValue(asp.resourceIDs_not_being_used, id) then
			table.insert(asp.resourceIDs_assigned_to_random, id);
			asp.iNumTypesRandom = asp.iNumTypesRandom + 1;
			if asp.iNumTypesDisabled > 0 then
				asp.iNumTypesDisabled = asp.iNumTypesDisabled - 1;
			end
			already = already + 1;
		end
		i = i + 1;
	end
end
------------------------------------------------------------------------------
local AssignLuxuryRolesVanilla = AssignStartingPlots.AssignLuxuryRoles;
function PromoteDisabledLuxuries(asp)
	if asp == nil or asp.resourceIDs_not_being_used == nil then
		return
	end
	local function nAssigned()
		local n = 0;
		if asp.resourceIDs_assigned_to_regions ~= nil then
			n = n + #asp.resourceIDs_assigned_to_regions;
		end
		if asp.resourceIDs_assigned_to_cs ~= nil then
			n = n + #asp.resourceIDs_assigned_to_cs;
		end
		if asp.resourceIDs_assigned_to_random ~= nil then
			n = n + #asp.resourceIDs_assigned_to_random;
		end
		if asp.resourceIDs_assigned_to_special_case ~= nil then
			n = n + #asp.resourceIDs_assigned_to_special_case;
		end
		return n;
	end
	local wantTypes = 15;
	if IsOasisClimate() then
		wantTypes = 24;
	end
	while nAssigned() < wantTypes and #asp.resourceIDs_not_being_used > 0 do
		local id = asp.resourceIDs_not_being_used[1];
		table.remove(asp.resourceIDs_not_being_used, 1);
		table.insert(asp.resourceIDs_assigned_to_random, id);
		asp.iNumTypesRandom = asp.iNumTypesRandom + 1;
		if asp.iNumTypesDisabled ~= nil and asp.iNumTypesDisabled > 0 then
			asp.iNumTypesDisabled = asp.iNumTypesDisabled - 1;
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:AssignLuxuryRoles()
	AssignLuxuryRolesVanilla(self);
	EnsureCoastalLuxCanAppear(self);
	PromoteDisabledLuxuries(self);
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceResourcesAndCityStates()
	local function step(name, method)
		WeeveeDbg("res " .. name);
		local ok, err = pcall(method, self);
		if ok then
			WeeveeDbg("res ok " .. name);
			return true
		end
		WeeveeDbg("ERR res " .. name .. " " .. tostring(err));
		return false
	end
	print("Map Generation - Assigning Luxury Resource Distribution");
	if step("AssignLuxuryRoles", self.AssignLuxuryRoles) == false then
		return
	end
	print("Map Generation - Placing City States");
	if step("PlaceCityStates", self.PlaceCityStates) == false then
		return
	end
	if step("GenerateGlobalResourcePlotLists", self.GenerateGlobalResourcePlotLists) == false then
		return
	end
	print("Map Generation - Placing Luxuries");
	if step("PlaceLuxuries", self.PlaceLuxuries) == false then
		return
	end
	if step("PlaceStrategicAndBonusResources", self.PlaceStrategicAndBonusResources) == false then
		return
	end
	print("Map Generation - Normalize City State Locations");
	step("NormalizeCityStateLocations", self.NormalizeCityStateLocations);
	pcall(self.AddForestToResource, self);
	pcall(self.FixSugarJungles, self);
	Map.RecalculateAreas();
	pcall(self.PrintFinalResourceTotalsToLog, self);
end
------------------------------------------------------------------------------
local PEAKS_VANILLA_FLAT_SHARE = 0.32;
function FilterMountainOutOfPlotList(plot_list)
	if plot_list == nil then
		return nil
	end
	local iW = Map.GetGridSize();
	local out = {};
	local i = 1;
	while plot_list[i] ~= nil do
		local plotIndex = plot_list[i];
		local x = (plotIndex - 1) % iW;
		local y = (plotIndex - x - 1) / iW;
		local plot = Map.GetPlot(x, y);
		if plot ~= nil and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
			table.insert(out, plotIndex);
		end
		i = i + 1;
	end
	return out
end
function PeaksScaleFrequency(self, frequency, plot_list)
	if frequency == nil or plot_list == nil then
		return frequency
	end
	if frequency >= 99999 then
		return frequency
	end
	local nList = table.maxn(plot_list);
	local nFlat = 0;
	if self ~= nil and self.land_list ~= nil then
		nFlat = table.maxn(self.land_list);
	end
	if nList < 1 or nFlat < 8 then
		return frequency
	end
	if nList * 2 <= nFlat then
		return frequency
	end
	local scale = nList / (nFlat * PEAKS_VANILLA_FLAT_SHARE);
	if scale < 1 then
		scale = 1;
	end
	return frequency * scale
end
local ProcessResourceListVanilla = AssignStartingPlots.ProcessResourceList;
function AssignStartingPlots:ProcessResourceList(frequency, impact_table_number, plot_list, resources_to_place)
	local cfg = GetBarrierConfig();
	if cfg ~= nil and resources_to_place ~= nil then
		if cfg.kind == "desert" then
			local i = 1;
			while resources_to_place[i] ~= nil do
				if resources_to_place[i][1] == self.banana_ID then
					frequency = frequency * 1.25;
					break
				end
				i = i + 1;
			end
		elseif cfg.kind == "tongue" then
			local i = 1;
			while resources_to_place[i] ~= nil do
				if resources_to_place[i][1] == self.banana_ID then
					frequency = frequency * 1.35;
					break
				end
				i = i + 1;
			end
		elseif cfg.kind == "wasteland" then
			local i = 1;
			local isDeer = false;
			while resources_to_place[i] ~= nil do
				if resources_to_place[i][1] == self.deer_ID then
					isDeer = true;
					break
				end
				i = i + 1;
			end
			if isDeer then
				local hillShare = 0.25;
				if plot_list == self.extra_deer_list then
					local nHill = table.maxn(plot_list);
					local nFlat = table.maxn(self.tundra_flat_no_feature);
					if nHill < 1 or nFlat < 1 then
						frequency = 99999;
					else
						local bonus = frequency / 10;
						if bonus < 0.1 then
							bonus = 1;
						end
						local totalWant = math.ceil(nFlat / (12 * bonus * 1.311));
						local hillWant = math.floor(totalWant * hillShare + 0.5);
						if hillWant < 1 then
							hillWant = 1;
						end
						frequency = nHill / hillWant;
						print("Wasteland deer quota: total", totalWant, " hills", hillWant, " flats list", nFlat);
					end
				elseif plot_list == self.tundra_flat_no_feature then
					if table.maxn(self.extra_deer_list) > 0 then
						frequency = frequency * 1.311 / (1 - hillShare);
					else
						frequency = frequency * 1.311;
					end
				else
					frequency = frequency * 1.311;
				end
			end
		elseif cfg.kind == "wetland" then
			local i = 1;
			while resources_to_place[i] ~= nil do
				if resources_to_place[i][1] == self.deer_ID then
					frequency = frequency * 1.111;
					if plot_list == self.extra_deer_list then
						frequency = frequency * 1.8;
					elseif plot_list == self.tundra_flat_no_feature then
						frequency = frequency * 1.55;
					end
					break
				elseif resources_to_place[i][1] == self.stone_ID then
					if plot_list == self.tundra_flat_no_feature then
						frequency = frequency * 0.68;
					end
					break
				end
				i = i + 1;
			end
		end
	end
	if cfg ~= nil and cfg.kind == "peaks" then
		frequency = PeaksScaleFrequency(self, frequency, plot_list);
	end
	return ProcessResourceListVanilla(self, frequency, impact_table_number, FilterMountainOutOfPlotList(plot_list), resources_to_place);
end
local PlaceSmallQuantitiesOfStrategicsVanilla = AssignStartingPlots.PlaceSmallQuantitiesOfStrategics;
function AssignStartingPlots:PlaceSmallQuantitiesOfStrategics(frequency, plot_list)
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "peaks" then
		frequency = PeaksScaleFrequency(self, frequency, plot_list);
	end
	return PlaceSmallQuantitiesOfStrategicsVanilla(self, frequency, FilterMountainOutOfPlotList(plot_list));
end
------------------------------------------------------------------------------
local AddStrategicBalanceResourcesVanilla = AssignStartingPlots.AddStrategicBalanceResources;
function AssignStartingPlots:AddStrategicBalanceResources(region_number)
	AddStrategicBalanceResourcesVanilla(self, region_number);
	if IsBramble() then
		local start_point_data = self.startingPlots[region_number];
		if start_point_data ~= nil then
			local sx = start_point_data[1];
			local sy = start_point_data[2];
			local oilID = GameInfoTypes["RESOURCE_OIL"];
			local alumID = GameInfoTypes["RESOURCE_ALUMINUM"];
			local uranID = GameInfoTypes["RESOURCE_URANIUM"];
			local yy = sy - 3;
			while yy <= sy + 3 do
				local xx = sx - 3;
				while xx <= sx + 3 do
					if Map.PlotDistance(sx, sy, xx, yy) <= 3 then
						local plot = Map.GetPlot(xx, yy);
						if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
							local res = plot:GetResourceType(-1);
							if res ~= -1 and res ~= oilID and res ~= alumID and res ~= uranID then
								plot:SetResourceType(-1);
							end
						end
					end
					xx = xx + 1;
				end
				yy = yy + 1;
			end
		end
	end
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local start_point_data = self.startingPlots[region_number];
	if start_point_data == nil then
		return
	end
	local sx = start_point_data[1];
	local sy = start_point_data[2];
	local iW, iH = Map.GetGridSize();
	local _, _, _, iron_amt = self:GetMajorStrategicResourceQuantityValues();
	if iron_amt == nil or iron_amt < 4 then
		iron_amt = 6;
	end
	local hills = {};
	local flats = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local d = Map.PlotDistance(sx, sy, x, y);
			if d >= 1 and d <= 2 then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if plot:GetResourceType(-1) == self.iron_ID then
						if plot:GetNumResource() >= 4 then
							return
						end
					end
					if plot:GetResourceType(-1) == -1 then
						if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
							table.insert(hills, plot);
						elseif plot:GetPlotType() == PlotTypes.PLOT_LAND then
							table.insert(flats, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local pick = nil;
	if #hills > 0 then
		hills = GetShuffledCopyOfTable(hills);
		pick = hills[1];
	elseif #flats > 0 then
		flats = GetShuffledCopyOfTable(flats);
		pick = flats[1];
		pick:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
	end
	if pick ~= nil then
		pick:SetResourceType(self.iron_ID, iron_amt);
		self.amounts_of_resources_placed[self.iron_ID + 1] = self.amounts_of_resources_placed[self.iron_ID + 1] + iron_amt;
		print("Peaks start iron at", pick:GetX(), pick:GetY(), " region", region_number);
	end
end
------------------------------------------------------------------------------
function PeakEnsureStartHills(asp)
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local r = 1;
	while asp.startingPlots[r] ~= nil do
		local sp = asp.startingPlots[r];
		local sx = sp[1];
		local sy = sp[2];
		local nHill = 0;
		local flats = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				local d = Map.PlotDistance(sx, sy, x, y);
				if d >= 1 and d <= 2 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
							nHill = nHill + 1;
						elseif plot:GetPlotType() == PlotTypes.PLOT_LAND then
							table.insert(flats, plot);
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if nHill < 2 then
			flats = GetShuffledCopyOfTable(flats);
			local need = 2 - nHill;
			local i = 1;
			local made = 0;
			while made < need and i <= #flats do
				flats[i]:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				made = made + 1;
				i = i + 1;
			end
			print("Peaks start hills region", r, " had", nHill, " added", made);
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
function FrostyTileOnSnow(plot)
	return plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW;
end
------------------------------------------------------------------------------
function FrostyStartLandOk(plot, skip)
	if plot == nil or plot:IsWater() then
		return false
	end
	if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	if FrostyTileOnSnow(plot) then
		return false
	end
	local iW, iH = Map.GetGridSize();
	if StartYAllowed(plot:GetY(), iH) == false then
		return false
	end
	local x = plot:GetX();
	if skip[x] == true then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function FrostyFixSnowStarts()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local skip = FillMireSkip(iW);
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local plot = player:GetStartingPlot();
			if IsMirrorEastSubject(plot:GetX(), plot:GetY()) == false and FrostyTileOnSnow(plot) then
				local px = plot:GetX();
				local py = plot:GetY();
				local x0 = 0;
				local x1 = mid - 1;
				if px >= mid then
					x0 = mid;
					x1 = iW - 1;
				end
				local bestX = nil;
				local bestY = nil;
				local bestD = 9999;
				local y = 0;
				while y < iH do
					local x = x0;
					while x <= x1 do
						local p = Map.GetPlot(x, y);
						if FrostyStartLandOk(p, skip) then
							local d = Map.PlotDistance(px, py, x, y);
							if d < bestD then
								bestD = d;
								bestX = x;
								bestY = y;
							end
						end
						x = x + 1;
					end
					y = y + 1;
				end
				if bestX ~= nil then
					player:SetStartingPlot(Map.GetPlot(bestX, bestY));
					print("Frosty post-mirror snow start moved", px, py, "to", bestX, bestY);
				end
			end
		end
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function FrostyThawStartResources()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local n = 0;
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local sp = player:GetStartingPlot();
			local sx = sp:GetX();
			local sy = sp:GetY();
			if IsMirrorEastSubject(sx, sy) == false then
				local y = 0;
				while y < iH do
					local x = 0;
					while x < iW do
						local dx = x - sx;
						if dx < 0 then
							dx = 0 - dx;
						end
						if dx <= 3 and Map.PlotDistance(sx, sy, x, y) <= 3 then
							local plot = Map.GetPlot(x, y);
							if plot ~= nil and plot:IsWater() == false then
								local t = plot:GetTerrainType();
								if t == TerrainTypes.TERRAIN_SNOW then
									local nGrass = CountAdjacentTerrain(plot, TerrainTypes.TERRAIN_GRASS);
									local nPlains = CountAdjacentTerrain(plot, TerrainTypes.TERRAIN_PLAINS);
									local nSnow = CountAdjacentTerrain(plot, TerrainTypes.TERRAIN_SNOW);
									if nSnow >= 1 and (nGrass + nPlains) < 4 then
										local res = plot:GetResourceType(-1);
										if res ~= nil and res ~= -1 then
											local usage = Game.GetResourceUsageType(res);
											local thaw = false;
											if usage == ResourceUsageTypes.RESOURCEUSAGE_LUXURY or usage == ResourceUsageTypes.RESOURCEUSAGE_STRATEGIC then
												thaw = true;
											elseif usage == ResourceUsageTypes.RESOURCEUSAGE_BONUS then
												if plot:GetFeatureType() ~= FeatureTypes.FEATURE_FOREST then
													thaw = true;
												end
											end
											if thaw then
												plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
												n = n + 1;
											end
										end
									end
								end
							end
						end
						x = x + 1;
					end
					y = y + 1;
				end
			end
		end
		i = i + 1;
	end
	print("Frosty thawed start snow resources:", n);
end
------------------------------------------------------------------------------
local START_TILE_RESOURCE_CHANCE = 8;
function MaybePlaceStartTileResource(asp)
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local r = 1;
	while asp.startingPlots[r] ~= nil do
		local sp = asp.startingPlots[r];
		local sx = sp[1];
		local sy = sp[2];
		local skipMirrorDest = (DEF_MIRRORED == 1 and sx >= iW / 2);
		if not skipMirrorDest and Map.Rand(100, "Start tile resource - Lua") < START_TILE_RESOURCE_CHANCE then
			local startPlot = Map.GetPlot(sx, sy);
			if startPlot ~= nil and startPlot:GetResourceType(-1) == -1 then
				local candidates = {};
				local y = 0;
				while y < iH do
					local x = 0;
					while x < iW do
						local d = Map.PlotDistance(sx, sy, x, y);
						if d >= 1 and d <= 3 then
							local plot = Map.GetPlot(x, y);
							if plot ~= nil then
								local resID = plot:GetResourceType(-1);
								if resID ~= -1 and IsWeeveeLuxuryID(resID) == false then
									local usage = Game.GetResourceUsageType(resID);
									if usage == ResourceUsageTypes.RESOURCEUSAGE_BONUS then
										if startPlot:CanHaveResource(resID) then
											table.insert(candidates, plot);
										end
									end
								end
							end
						end
						x = x + 1;
					end
					y = y + 1;
				end
				local n = #candidates;
				if n > 0 then
					local src = candidates[1 + Map.Rand(n, "Start tile resource pick - Lua")];
					local resID = src:GetResourceType(-1);
					local num = src:GetNumResource();
					src:SetResourceType(-1);
					startPlot:SetResourceType(resID, num);
					print("Start tile resource region", r, " moved", resID, "qty", num);
				end
			end
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
-- The global rule is: a start plot may share a tile with a bonus resource
-- (MaybePlaceStartTileResource above even does this deliberately), but never
-- with a strategic or luxury resource. That rule is enforced correctly at
-- placement time -- against wherever each start plot is *then*. What isn't
-- covered: ClampPlayerStartsOffEdges/NudgePlayerStartsMinDist run again as a
-- late safety net (after Natural Wonders, all resources, and the mirror
-- copy) to fix a start that ended up too close to another or off a climate
-- edge, and FindNearestStartOffEdge's candidate search has no idea what
-- resources already sit on a candidate tile. On a tight map (Standard-
-- Diagonal's small canvas plus a chunky diagonal barrier eating playable
-- space) this late relocation fires more often, so it's the one path that
-- can hand a player a final start tile still carrying a strategic/luxury
-- resource nobody ever re-checked. Run last, once starts are truly final.
function StripNonBonusStartTileResources()
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local n = 0;
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() then
			local plot = player:GetStartingPlot();
			if plot ~= nil and IsMirrorEastSubject(plot:GetX(), plot:GetY()) == false then
				local resID = plot:GetResourceType(-1);
				if resID ~= -1 and Game.GetResourceUsageType(resID) ~= ResourceUsageTypes.RESOURCEUSAGE_BONUS then
					plot:SetResourceType(-1);
					n = n + 1;
				end
			end
		end
		i = i + 1;
	end
	print("Non-bonus resources stripped off final start tiles:", n);
end
------------------------------------------------------------------------------
local MIN_START_LANDMASS = 6;
local START_EDGE_MIN = 4;
function StartYAllowed(y, iH)
	if y == nil or iH == nil then
		return false
	end
	if iH <= START_EDGE_MIN * 2 then
		return y > 0 and y < iH - 1;
	end
	return y >= START_EDGE_MIN and y < iH - START_EDGE_MIN;
end
------------------------------------------------------------------------------
local START_MIN_SALT_WATER_DIST = 3;
function SaltWaterWithin(x, y, maxD)
	if x == nil or y == nil then
		return false
	end
	if maxD == nil or maxD < 1 then
		maxD = 1;
	end
	local dy = y - maxD;
	while dy <= y + maxD do
		local dx = x - maxD;
		while dx <= x + maxD do
			if Map.PlotDistance(x, y, dx, dy) <= maxD then
				local p = Map.GetPlot(dx, dy);
				if p ~= nil and p:IsWater() and p:IsLake() == false then
					return true
				end
			end
			dx = dx + 1;
		end
		dy = dy + 1;
	end
	return false
end
------------------------------------------------------------------------------
function OasisStartOk(x, y)
	if IsOasisClimate() == false then
		return true
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil or plot:IsWater() or plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	local iW = Map.GetGridSize();
	if OasisIsWestHinterlandX(x, iW) then
		return false
	end
	local skip = FillMireSkip(iW);
	if skip[x] == true then
		return false
	end
	if SaltWaterWithin(x, y, 2) then
		return false
	end
	local nNonDesert = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil
			and adj:IsWater() == false
			and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
			and adj:GetTerrainType() ~= TerrainTypes.TERRAIN_DESERT then
			nNonDesert = nNonDesert + 1;
		end
		d = d + 1;
	end
	return nNonDesert >= 2;
end
------------------------------------------------------------------------------
-- Mirror symmetry must be absolute: nothing may independently move or mutate
-- a plot/start on the non-canonical (east) side after generation -- the only
-- thing ever allowed to determine east's final state is the west-to-east
-- copy pass (MirrorPlotsAfterResourcePlacement/getMirroredPlot). These three
-- helpers let every late "safety net" pass (edge/tongue clamping, min-dist
-- nudging, Frosty snow-start fixups, start-tile resource/terrain cleanup)
-- restrict itself to west-side subjects only, while still reasoning
-- correctly about spacing against where east's mirrored partners will end
-- up once the copy runs.
function IsMirrorEastSubject(x, y)
	if DEF_MIRRORED ~= 1 then
		return false
	end
	local iW = Map.GetGridSize();
	return MirrorOwnsPlot(x, y, true, iW) == false;
end
------------------------------------------------------------------------------
function MirroredXY(x, y)
	local iW, iH = Map.GetGridSize();
	return iW - x - 1, iH - y - 1;
end
------------------------------------------------------------------------------
-- Builds the "others" list for a west-side subject (player index excludeIndex)
-- as every other currently-west-positioned player's real position, plus the
-- future mirror-image position of every west-positioned player (including
-- the subject's own east partner) -- i.e. every real final position on the
-- map except the subject itself. Stale/raw east-side positions (not yet
-- synced to their west partner's mirror image) are never used directly, so
-- spacing decisions never depend on data the final copy is about to discard.
-- On non-mirrored maps this just returns every other alive player, unchanged.
function GatherMirrorAwareOthers(excludeIndex)
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local others = {};
	local j = 0;
	while j < nMaj do
		local p = Players[j];
		if p ~= nil and p:IsAlive() and p:GetStartingPlot() ~= nil then
			local px = p:GetStartingPlot():GetX();
			local py = p:GetStartingPlot():GetY();
			if IsMirrorEastSubject(px, py) == false then
				if j ~= excludeIndex then
					table.insert(others, {px, py});
				end
				if mirrored then
					local mx, my = MirroredXY(px, py);
					table.insert(others, {mx, my});
				end
			end
		end
		j = j + 1;
	end
	return others;
end
------------------------------------------------------------------------------
function StartMinDistToList(x, y, others)
	local best = 9999;
	local i = 1;
	while i <= #others do
		if others[i][1] ~= nil and others[i][2] ~= nil then
			local d = Map.PlotDistance(x, y, others[i][1], others[i][2]);
			if d < best then
				best = d;
			end
		end
		i = i + 1;
	end
	return best
end
------------------------------------------------------------------------------
function FindNearestStartOffEdge(sx, sy, others, minSep)
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	if minSep == nil then
		minSep = 5;
	end
	local x0 = 0;
	local x1 = iW - 1;
	if DEF_MIRRORED == 1 then
		if sx < mid then
			x1 = mid - 1;
		else
			x0 = mid;
		end
	end
	local cfg = GetBarrierConfig();
	if others == nil then
		others = {};
	end
	local bestX = nil;
	local bestY = nil;
	local bestD = 9999;
	local bestSepX = nil;
	local bestSepY = nil;
	local bestSep = -1;
	local bestSepNear = 9999;
	local y = 0;
	while y < iH do
		if StartYAllowed(y, iH) then
			local x = x0;
			while x <= x1 do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					local ok = true;
					if cfg ~= nil and cfg.kind == "frosty" and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
						ok = false;
					end
					if ok and TongueStartTooClose(x, y) then
						ok = false;
					end
					if ok and OasisStartOk(x, y) == false then
						ok = false;
					end
					if ok and SaltWaterWithin(x, y, START_MIN_SALT_WATER_DIST) then
						ok = false;
					end
					if ok then
						local d = Map.PlotDistance(sx, sy, x, y);
						local sep = StartMinDistToList(x, y, others);
						if sep >= minSep and d < bestD then
							bestD = d;
							bestX = x;
							bestY = y;
						end
						if sep > bestSep or (sep == bestSep and d < bestSepNear) then
							bestSep = sep;
							bestSepNear = d;
							bestSepX = x;
							bestSepY = y;
						end
					end
				end
				x = x + 1;
			end
		end
		y = y + 1;
	end
	if bestX ~= nil then
		return bestX, bestY;
	end
	return bestSepX, bestSepY;
end
------------------------------------------------------------------------------
function OasisSpreadStarts(asp)
	if IsOasisClimate() == false then
		return
	end
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local iW = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local pass = 1;
	while pass <= 12 do
		local moved = false;
		local r = 1;
		while asp.startingPlots[r] ~= nil do
			local sp = asp.startingPlots[r];
			if sp[1] ~= nil and sp[1] < mid then
				local others = {};
				local o = 1;
				while asp.startingPlots[o] ~= nil do
					if o ~= r then
						table.insert(others, {asp.startingPlots[o][1], asp.startingPlots[o][2]});
					end
					o = o + 1;
				end
				local dMin = StartMinDistToList(sp[1], sp[2], others);
				if dMin < 6 then
					local nx, ny = FindNearestStartOffEdge(sp[1], sp[2], others, 6);
					if nx ~= nil and (nx ~= sp[1] or ny ~= sp[2]) then
						asp.startingPlots[r] = {nx, ny, 1};
						print("Oasis start spread region", r, "from", sp[1], sp[2], "to", nx, ny, "was", dMin);
						moved = true;
					end
				end
			end
			r = r + 1;
		end
		if moved == false then
			break
		end
		pass = pass + 1;
	end
end
------------------------------------------------------------------------------
local weeveeStartDistFail = false;
function EnforceMinStartDistance(asp, minDist)
	if minDist == nil then
		minDist = 7;
	end
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local iW = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local pass = 1;
	while pass <= 12 do
		local moved = false;
		local r = 1;
		while asp.startingPlots[r] ~= nil do
			local sp = asp.startingPlots[r];
			if sp[1] ~= nil and ((DEF_MIRRORED ~= 1) or (sp[1] < mid)) then
				local others = {};
				local o = 1;
				while asp.startingPlots[o] ~= nil do
					if o ~= r then
						table.insert(others, {asp.startingPlots[o][1], asp.startingPlots[o][2]});
					end
					o = o + 1;
				end
				local dMin = StartMinDistToList(sp[1], sp[2], others);
				if dMin < minDist then
					local nx, ny = FindNearestStartOffEdge(sp[1], sp[2], others, minDist);
					if nx ~= nil and StartMinDistToList(nx, ny, others) >= minDist then
						print("Start min-dist region", r, "from", sp[1], sp[2], "to", nx, ny, "was", dMin);
						asp.startingPlots[r] = {nx, ny, 1};
						moved = true;
					end
				end
			end
			r = r + 1;
		end
		if moved == false then
			break
		end
		pass = pass + 1;
	end
	local r = 1;
	while asp.startingPlots[r] ~= nil do
		local sp = asp.startingPlots[r];
		if sp[1] ~= nil and ((DEF_MIRRORED ~= 1) or (sp[1] < mid)) then
			local others = {};
			local o = 1;
			while asp.startingPlots[o] ~= nil do
				if o ~= r then
					table.insert(others, {asp.startingPlots[o][1], asp.startingPlots[o][2]});
				end
				o = o + 1;
			end
			if StartMinDistToList(sp[1], sp[2], others) < minDist then
				weeveeStartDistFail = true;
				print("Start min-dist still failed region", r, sp[1], sp[2]);
			end
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
function NudgePlayerStartsMinDist(minDist)
	if minDist == nil then
		minDist = 7;
	end
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local pass = 1;
	while pass <= 8 do
		local moved = false;
		local i = 0;
		while i < nMaj do
			local player = Players[i];
			if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
				local sx = player:GetStartingPlot():GetX();
				local sy = player:GetStartingPlot():GetY();
				if IsMirrorEastSubject(sx, sy) == false then
					local others = GatherMirrorAwareOthers(i);
					if StartMinDistToList(sx, sy, others) < minDist then
						local nx, ny = FindNearestStartOffEdge(sx, sy, others, minDist);
						if nx ~= nil and StartMinDistToList(nx, ny, others) >= minDist then
							player:SetStartingPlot(Map.GetPlot(nx, ny));
							print("Player start min-dist", i, "from", sx, sy, "to", nx, ny);
							moved = true;
						end
					end
				end
			end
			i = i + 1;
		end
		if moved == false then
			break
		end
		pass = pass + 1;
	end
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local sx = player:GetStartingPlot():GetX();
			local sy = player:GetStartingPlot():GetY();
			if IsMirrorEastSubject(sx, sy) == false then
				local others = GatherMirrorAwareOthers(i);
				if StartMinDistToList(sx, sy, others) < minDist then
					weeveeStartDistFail = true;
					print("Player start min-dist still failed", i);
				end
			end
		end
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function ClampAspStartsOffEdges(asp)
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local r = 1;
	while asp.startingPlots[r] ~= nil do
		local sp = asp.startingPlots[r];
		local sx = sp[1];
		local sy = sp[2];
		if sx ~= nil and sy ~= nil then
			local needMove = false;
			if StartYAllowed(sy, iH) == false then
				needMove = true;
			end
			if TongueStartTooClose(sx, sy) then
				needMove = true;
			end
			if OasisStartOk(sx, sy) == false then
				needMove = true;
			end
			if SaltWaterWithin(sx, sy, START_MIN_SALT_WATER_DIST) then
				needMove = true;
			end
			if needMove then
				local others = {};
				local o = 1;
				while asp.startingPlots[o] ~= nil do
					if o ~= r then
						table.insert(others, {asp.startingPlots[o][1], asp.startingPlots[o][2]});
					end
					o = o + 1;
				end
				local nx, ny = FindNearestStartOffEdge(sx, sy, others);
				if nx ~= nil then
					asp.startingPlots[r] = {nx, ny, 1};
					print("Start moved off edge/tongue region", r, "from", sx, sy, "to", nx, ny);
				end
			end
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
function ClampPlayerStartsOffEdges()
	local iW, iH = Map.GetGridSize();
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local plot = player:GetStartingPlot();
			local sx = plot:GetX();
			local sy = plot:GetY();
			if IsMirrorEastSubject(sx, sy) == false then
				if StartYAllowed(sy, iH) == false or TongueStartTooClose(sx, sy) or OasisStartOk(sx, sy) == false or SaltWaterWithin(sx, sy, START_MIN_SALT_WATER_DIST) then
					local others = GatherMirrorAwareOthers(i);
					local nx, ny = FindNearestStartOffEdge(sx, sy, others);
					if nx ~= nil then
						player:SetStartingPlot(Map.GetPlot(nx, ny));
						print("Player start moved off edge/tongue", i, "from", sx, sy, "to", nx, ny);
					end
				end
			end
		end
		i = i + 1;
	end
end
------------------------------------------------------------------------------
local EvaluateCandidatePlotVanilla = AssignStartingPlots.EvaluateCandidatePlot;
function AssignStartingPlots:EvaluateCandidatePlot(plotIndex, region_type)
	local iW, iH = Map.GetGridSize();
	local x = (plotIndex - 1) % iW;
	local y = (plotIndex - x - 1) / iW;
	if StartYAllowed(y, iH) == false then
		return -200, false;
	end
	local plot = Map.GetPlot(x, y);
	if plot ~= nil and not plot:IsWater() then
		local area = plot:Area();
		if area ~= nil and area:GetNumTiles() < MIN_START_LANDMASS then
			return -200, false;
		end
		local cfg = GetBarrierConfig();
		if cfg ~= nil and cfg.kind == "frosty" and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
			return -200, false;
		end
		if TongueStartTooClose(x, y) then
			return -200, false;
		end
	end
	local score, ok = EvaluateCandidatePlotVanilla(self, plotIndex, region_type);
	if OasisStartOk(x, y) == false then
		if score == nil or score < 1 then
			score = 1;
		end
		return score, false;
	end
	if self.startingPlots ~= nil then
		local r = 1;
		while self.startingPlots[r] ~= nil do
			local sp = self.startingPlots[r];
			if sp[1] ~= nil and sp[2] ~= nil then
				if Map.PlotDistance(x, y, sp[1], sp[2]) < 5 then
					return -200, false;
				end
			end
			r = r + 1;
		end
	end
	return score, ok;
end
local MeasureFertilityOfPlotVanilla = AssignStartingPlots.MeasureStartPlacementFertilityOfPlot;
function AssignStartingPlots:MeasureStartPlacementFertilityOfPlot(x, y, checkForCoastalLand)
	if TongueStartTooClose(x, y) then
		return 0
	end
	if OasisIsWestHinterlandX(x) then
		return 0
	end
	return MeasureFertilityOfPlotVanilla(self, x, y, checkForCoastalLand);
end
local PlaceImpactAndRipplesVanilla = AssignStartingPlots.PlaceImpactAndRipples;
function AssignStartingPlots:PlaceImpactAndRipples(x, y)
	if x == nil or y == nil then
		return
	end
	return PlaceImpactAndRipplesVanilla(self, x, y);
end
-- Oasis: bump deferred lux (impact 2, max_radius ≤ 1) to at least ripple 1.
-- Do NOT convert impact -1: that ignore-overlay path is how vanilla plants
-- regionals on the capital after PlaceImpactAndRipples already stamped r=3.
local PlaceSpecificNumberOfResourcesVanilla = AssignStartingPlots.PlaceSpecificNumberOfResources;
function AssignStartingPlots:PlaceSpecificNumberOfResources(resource_ID, quantity, amount, ratio, impact_table_number, min_radius, max_radius, plot_list)
	if IsWeeveeLuxuryID(resource_ID) and plot_list ~= nil then
		local starts = WeeveeMajorStartIndexSet();
		local filtered = {};
		local i = 1;
		while plot_list[i] ~= nil do
			if starts[plot_list[i]] ~= true then
				table.insert(filtered, plot_list[i]);
			end
			i = i + 1;
		end
		plot_list = filtered;
	end
	if IsOasisClimate() and IsWeeveeLuxuryID(resource_ID) then
		if impact_table_number == 2 then
			local maxR = max_radius;
			if maxR == nil then
				maxR = min_radius;
			end
			if maxR <= 1 then
				if min_radius == nil or min_radius < 1 then
					min_radius = 1;
				end
				if max_radius == nil or max_radius < 1 then
					max_radius = 1;
				end
			end
		end
	end
	plot_list = FilterMountainOutOfPlotList(plot_list);
	return PlaceSpecificNumberOfResourcesVanilla(self, resource_ID, quantity, amount, ratio, impact_table_number, min_radius, max_radius, plot_list);
end
local FindStartVanilla = AssignStartingPlots.FindStart;
function AssignStartingPlots:FindStart(region_number)
	local ok, forced = FindStartVanilla(self, region_number);
	if self.startingPlots[region_number] ~= nil then
		local sp = self.startingPlots[region_number];
		if sp[1] == nil or sp[2] == nil then
			local nx, ny = FindNearestStartOffEdge(0, 0, {});
			if nx ~= nil then
				self.startingPlots[region_number] = {nx, ny, 1};
				self:PlaceImpactAndRipples(nx, ny);
			end
		end
	end
	if ok and self.startingPlots[region_number] ~= nil then
		local sx = self.startingPlots[region_number][1];
		local sy = self.startingPlots[region_number][2];
		local plot = Map.GetPlot(sx, sy);
		if plot ~= nil then
			local area = plot:Area();
			if area ~= nil and area:GetNumTiles() < MIN_START_LANDMASS then
				print("Start on tiny island at", sx, sy, "- relocating");
				local iW, iH = Map.GetGridSize();
				local bestSep = -1;
				local bestX, bestY;
				for ry = 0, iH - 1 do
					for rx = 0, iW - 1 do
						local p = Map.GetPlot(rx, ry);
						if p ~= nil and not p:IsWater() and p:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and StartYAllowed(ry, iH) then
							if TongueStartTooClose(rx, ry) == false and OasisStartOk(rx, ry) then
							local a = p:Area();
							if a ~= nil and a:GetNumTiles() >= MIN_START_LANDMASS then
								local minD = 9999;
								local oi = 1;
								while self.startingPlots[oi] ~= nil do
									if oi ~= region_number then
										local osp = self.startingPlots[oi];
										if osp ~= nil then
											local d = Map.PlotDistance(rx, ry, osp[1], osp[2]);
											if d < minD then
												minD = d;
											end
										end
									end
									oi = oi + 1;
								end
								if minD > bestSep then
									bestSep = minD;
									bestX = rx;
									bestY = ry;
								end
							end
							end
						end
					end
				end
				if bestX ~= nil then
					self.startingPlots[region_number] = {bestX, bestY, 1};
					print("Relocated start to", bestX, bestY, "sep", bestSep);
				end
			end
		end
	end
	return ok, forced;
end
------------------------------------------------------------------------------
local ChooseLocationsVanilla = AssignStartingPlots.ChooseLocations;
function AssignStartingPlots:ChooseLocations(args)
	WeeveeDbg("ChooseLocations nReg=" .. tostring(table.maxn(self.regionData)));
	local ok, err = pcall(ChooseLocationsVanilla, self, args);
	if ok then
		WeeveeDbg("ChooseLocations ok");
	else
		WeeveeDbg("ChooseLocations ERR " .. tostring(err));
		print("ChooseLocations ERR", err);
	end
end
------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function GetMapInitData(worldSize)
	WeeveeDbgReset();
	ResetWeeveeGenState();
	WeeveeDbg("GetMapInitData");
	ResolveBarrierSplit();
	ResolveWrap();
	local cfg = GetBarrierConfig();
	local kind = "nil";
	if cfg ~= nil then
		kind = tostring(cfg.kind);
	end
	WeeveeDbg("split wrap kind=" .. kind .. " wrapX=" .. tostring(IsSnowWrapX()));
	-- This function can reset map grid sizes or world wrap settings.
	--
	-- East vs West is an extremely compact multiplayer map type.
	local worldsizes = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {34, 14},
		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {40, 22},
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {44, 26},
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {50, 30},
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {52, 32},
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {64, 40}
		}
	local grid_size = worldsizes[worldSize];
	--
	local world = GameInfo.Worlds[worldSize];
	if(world ~= nil) then
		if grid_size == nil then
			print("Weevee GetMapInitData: unknown worldSize", worldSize);
			return
		end
		local w = grid_size[1];
		local h = grid_size[2];
		if IsExploBalance() then
			w = w - 4;
		end
		if cfg ~= nil and cfg.kind == "desert" then
			local extra = OasisWestDesertColumns();
			if DEF_MIRRORED == 1 then
				w = w + extra * 2;
			else
				w = w + extra;
			end
		end
		if cfg ~= nil and cfg.kind == "frosty" then
			if DEF_MIRRORED == 1 then
				w = w + 8;
			else
				w = w + 4;
			end
		end
		if cfg ~= nil and cfg.tilted == true then
			-- The tilted barrier's row-mirroring math needs a map height that's
			-- a multiple of 4 to be simultaneously exact-width and visually
			-- straight (see the Standard-Diagonal width/smoothness investigation).
			-- Small/Tiny's default height (22) isn't, so pin it to one that is.
			h = 20;
			w = w + 6;
		end
		print("Map canvas:", w, "x", h, "(base", grid_size[1], "x", grid_size[2], ")");
		WeeveeDbg("canvas " .. tostring(w) .. "x" .. tostring(h) .. " wrapX=" .. tostring(IsSnowWrapX()));
		return {
			Width = w,
			Height = h,
			WrapX = IsSnowWrapX(),
		};
	end
end
-------------------------------------------------------------------------------
local snowWrapWidthResolved = false;
local snowWrapBackWidth = 0;
local snowWrapCenterWidth = 0;
function ResolveSnowWrapWidths()
	if snowWrapWidthResolved then
		return snowWrapBackWidth, snowWrapCenterWidth;
	end
	snowWrapWidthResolved = true;
	local ops = BARRIER_WIDTH_FROZEN_OPS;
	if IsSnowWrapX() == false then
		snowWrapBackWidth = 0;
		if ops == 5 then
			snowWrapCenterWidth = 2 * (Map.Rand(2, "Snow Wrap Center Width") + 1);
		else
			snowWrapCenterWidth = (ops - 1) * 2;
		end
		print("Snow Barrier widths (no wrap): wrap=0 center=", snowWrapCenterWidth);
		return snowWrapBackWidth, snowWrapCenterWidth;
	end
	if ops == 5 then
		repeat
			snowWrapBackWidth = 2 * (Map.Rand(3, "Snow Wrap Back Width") + 1);
			snowWrapCenterWidth = 2 * (Map.Rand(3, "Snow Wrap Center Width") + 1);
		until snowWrapBackWidth < 6 or snowWrapCenterWidth < 6;
		print("Snow Wrap widths (random): wrap=", snowWrapBackWidth, " center=", snowWrapCenterWidth);
	else
		local n = (ops - 1) * 2;
		snowWrapBackWidth = n;
		snowWrapCenterWidth = n;
	end
	return snowWrapBackWidth, snowWrapCenterWidth;
end
------------------------------------------------------------------------------
local climateScaleResolved = false;
local climateScale = 0.8;
local climateVariation = nil;
local luxTargetResolved = false;
local luxWantU = 15;
local luxWantD = 7;
local luxWantT = 3;
local frostyFrac = nil;
function ResetWeeveeGenState()
	barrierSplitResolved = false;
	barrierWrapResolved = false;
	saltPlanResolved = false;
	snowWrapWidthResolved = false;
	climateScaleResolved = false;
	climateVariation = nil;
	oasisJungleCached = false;
	oasisJungleExists = false;
	murkTundraLakeTiles = {};
	frostyFrac = nil;
	luxTargetResolved = false;
	weeveeStartDistFail = false;
end
function ResetWeeveeMapAttempt()
	local iW, iH = Map.GetGridSize();
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				if plot:GetResourceType(-1) ~= -1 then
					plot:SetResourceType(-1);
				end
				-- Only resources were cleared here before, so a discarded
				-- attempt's features -- most visibly Natural Wonders, since
				-- GeneratePlotTypes/GenerateTerrain repaint plot type/terrain
				-- fresh every attempt but nothing repaints features -- survived
				-- untouched into the next attempt and stacked with whatever it
				-- placed, doubling (or tripling, one per retry) the final count.
				if plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				end
				if plot:IsWOfRiver() or plot:IsNWOfRiver() or plot:IsNEOfRiver() then
					plot:SetWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
					plot:SetNWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
					plot:SetNEOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
				end
				-- AddGoodies (huts) runs once per attempt too, same accumulation risk.
				if plot:GetImprovementType() ~= -1 then
					plot:SetImprovementType(-1);
				end
			end
		end
	end
	-- DEFMapGeneratorW8's own river bookkeeping (_rivers, keyed by plot,
	-- tracking which riverID already claimed it) is a global set up once at
	-- script load, not reset per AddRivers() call -- unlike riverEdgeList,
	-- which AddRivers already re-inits itself. Left alone it would carry a
	-- discarded attempt's claims into the next attempt's DoRiver() calls.
	_rivers = {};
	saltPlanResolved = false;
	snowWrapWidthResolved = false;
	climateScaleResolved = false;
	climateVariation = nil;
	oasisJungleCached = false;
	oasisJungleExists = false;
	murkTundraLakeTiles = {};
	tongueJungleDepth = nil;
	brambleShapeReady = false;
	brambleLo = {};
	brambleHi = {};
	frostyFrac = nil;
	luxTargetResolved = false;
	weeveeStartDistFail = false;
end
function ResolveClimateScale()
	if climateScaleResolved then
		return climateScale, climateVariation;
	end
	climateScaleResolved = true;
	local iW, iH = Map.GetGridSize();
	local oneRow = 0.8 / (iH / 2);
	climateScale = 0.8 + (Map.Rand(3, "Climate Scale") - 1) * oneRow;
	if climateScale > 0.95 then
		climateScale = 0.95;
	end
	climateVariation = Fractal.Create(iW, iH, 3, Map.GetFractalFlags(), -1, -1);
	print("Climate scale:", climateScale);
	return climateScale, climateVariation;
end
------------------------------------------------------------------------------
function GetClimateLatitudeAtPlot(iX, iY)
	local scale, variation = ResolveClimateScale();
	local iW, iH = Map.GetGridSize();
	local lat = math.abs((iH / 2) - iY) / (iH / 2);
	lat = lat + (128 - variation:GetHeight(iX, iY)) / (255.0 * 5.0);
	lat = scale * (math.clamp(lat, 0, 1));
	return lat;
end
------------------------------------------------------------------------------
function GetSnowWrapWaterBounds(iW)
	local wrapN, centerN = ResolveSnowWrapWidths();
	local wrapHalf = wrapN / 2;
	local centerHalf = centerN / 2;
	local mid = math.floor(iW / 2);
	if IsBramble() then
		centerHalf = 0;
	end
	local minX = wrapHalf + 4;
	local maxX = mid - centerHalf - 5;
	if IsOasisClimate() then
		minX = minX + OasisWestDesertColumns();
	end
	return minX, maxX;
end
------------------------------------------------------------------------------
function OasisJungleOval(iW, iH)
	if iW == nil or iH == nil then
		iW, iH = Map.GetGridSize();
	end
	local mid = math.floor(iW / 2);
	local minX, maxX = GetSnowWrapWaterBounds(iW);
	if minX > maxX then
		minX = 1;
		maxX = mid - 2;
	end
	if maxX > mid - 1 then
		maxX = mid - 1;
	end
	local _, centerN = ResolveSnowWrapWidths();
	local frontX = mid - centerN / 2 - 2;
	if frontX > mid - 1 then
		frontX = mid - 1;
	end
	if frontX < maxX then
		frontX = maxX;
	end
	local hinter = OasisWestDesertColumns();
	if minX < hinter then
		minX = hinter;
	end
	local playW = frontX - hinter;
	if playW < 8 then
		playW = 8;
	end
	local lushRad = math.sqrt(0.90);
	local rx = playW * 0.42 * lushRad;
	local ry = iH * 0.26 * lushRad;
	if rx < 2 then
		rx = 2;
	end
	if ry < 2 then
		ry = 2;
	end
	local cx = frontX - rx * 0.88;
	local cy = (iH - 1) / 2;
	local maxDy = math.floor(iH * 0.35 * lushRad);
	local yLo = cy - maxDy;
	local yHi = cy + maxDy;
	if yLo < 0 then
		yLo = 0;
	end
	if yHi > iH - 1 then
		yHi = iH - 1;
	end
	return iW, iH, minX, maxX, frontX, cx, cy, rx, ry, yLo, yHi, maxDy, mid;
end
------------------------------------------------------------------------------
function OasisFrontMostColumns(iW, iH)
	local cols = {};
	if IsOasisClimate() == false then
		return cols
	end
	local _, _, _, _, frontX = OasisJungleOval(iW, iH);
	local x = frontX - 2;
	while x <= frontX do
		if x >= 0 and x < iW then
			table.insert(cols, x);
		end
		x = x + 1;
	end
	return cols
end
------------------------------------------------------------------------------
function PlaceOasisCrescentSeas(plotTypes, iW, iH)
	if plotTypes == nil or IsOasisClimate() == false then
		return
	end
	local _, _, minX, maxX, frontX, cx, cy, rx, ry = OasisJungleOval(iW, iH);
	local hinter = OasisWestDesertColumns();
	local wrx = rx * 1.15 * 1.15;
	local wry = ry * 1.15 * 1.15;
	local cyEdge = cy;
	if cyEdge < 1 then
		cyEdge = 1;
	end
	local wryEdge = cyEdge / math.sqrt(1.90);
	if wry < wryEdge then
		wry = wryEdge;
	end
	if wrx < 2 then
		wrx = 2;
	end
	if wry < 2 then
		wry = 2;
	end
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local function hexDirs(y)
		if y % 2 ~= 0 then
			return oddN
		end
		return evenN
	end
	local function onCrescent(x, y)
		if x < hinter or x > frontX or y < 0 or y > iH - 1 then
			return false
		end
		if WaterAllowedAtX(x) == false then
			return false
		end
		local ux = (x - cx) / wrx;
		local uy = (y - cy) / wry;
		local r2 = ux * ux + uy * uy;
		if r2 < 0.90 then
			return false
		end
		if ux > 0.22 and uy * uy < 0.50 then
			return false
		end
		if r2 <= 1.90 then
			return true
		end
		if uy * uy >= 1.0 and ux <= 0.22 and ux >= -1.90 then
			return true
		end
		return false
	end
	local function foreignOceanWithin(x, y, maxD, blobSet)
		if maxD == nil or maxD < 1 then
			return false
		end
		local dy = y - maxD;
		while dy <= y + maxD do
			local dx = x - maxD;
			while dx <= x + maxD do
				if dx >= 0 and dx < iW and dy >= 0 and dy < iH then
					if Map.PlotDistance(x, y, dx, dy) <= maxD then
						local idx = dy * iW + dx + 1;
						if plotTypes[idx] == PlotTypes.PLOT_OCEAN then
							if blobSet == nil or blobSet[idx] ~= true then
								return true
							end
						end
					end
				end
				dx = dx + 1;
			end
			dy = dy + 1;
		end
		return false
	end
	local north = {};
	local south = {};
	local west = {};
	local all = {};
	local y = 0;
	while y < iH do
		local x = hinter;
		while x <= frontX do
			if onCrescent(x, y) then
				local idx = y * iW + x + 1;
				local ptype = plotTypes[idx];
				if ptype ~= PlotTypes.PLOT_MOUNTAIN and ptype ~= PlotTypes.PLOT_OCEAN then
					local t = {x, y, idx};
					table.insert(all, t);
					if y <= cy - wry * 0.35 then
						table.insert(south, t);
					elseif y >= cy + wry * 0.35 then
						table.insert(north, t);
					elseif x <= cx then
						table.insert(west, t);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #all < 8 then
		print("Oasis crescent seas: no ring tiles", #all);
		return
	end
	local nBodies = 5 + Map.Rand(3, "Oasis Crescent Count");
	local nPaint = 0;
	local nOk = 0;
	local b = 1;
	while b <= nBodies do
		local pool = all;
		if b == 1 and #south > 0 then
			pool = south;
		elseif b == 2 and #north > 0 then
			pool = north;
		elseif b == 3 and #west > 0 then
			pool = west;
		end
		local seed = nil;
		local seedGap = 1 + Map.Rand(4, "Oasis Sea Gap");
		local attempt = 1;
		while attempt <= 90 and seed == nil do
			if #pool < 1 then
				pool = all;
			end
			if #pool < 1 then
				break
			end
			local t = pool[Map.Rand(#pool, "Oasis Crescent Seed") + 1];
			if plotTypes[t[3]] ~= PlotTypes.PLOT_OCEAN and plotTypes[t[3]] ~= PlotTypes.PLOT_MOUNTAIN then
				if onCrescent(t[1], t[2]) and foreignOceanWithin(t[1], t[2], seedGap, nil) == false then
					seed = t;
				end
			end
			if seed == nil and attempt == 45 and seedGap > 1 then
				seedGap = seedGap - 1;
			end
			attempt = attempt + 1;
		end
		if seed ~= nil then
			nOk = nOk + 1;
			local lakeSize = 5 + Map.Rand(5, "Oasis Crescent Size");
			local blob = {{seed[1], seed[2]}};
			local blobSet = {};
			blobSet[seed[3]] = true;
			plotTypes[seed[3]] = PlotTypes.PLOT_OCEAN;
			nPaint = nPaint + 1;
			local grown = 1;
			local step = 0;
			while grown < lakeSize do
				step = step + 1;
				if step > 110 then
					break
				end
				local candidates = {};
				local pIndex = 1;
				while pIndex <= #blob do
					local p = blob[pIndex];
					local dirs = hexDirs(p[2]);
					local dIndex = 1;
					while dIndex <= 6 do
						local nx = p[1] + dirs[dIndex][1];
						local ny = p[2] + dirs[dIndex][2];
						if onCrescent(nx, ny) then
							local nidx = ny * iW + nx + 1;
							if plotTypes[nidx] ~= PlotTypes.PLOT_OCEAN and plotTypes[nidx] ~= PlotTypes.PLOT_MOUNTAIN then
								if foreignOceanWithin(nx, ny, seedGap, blobSet) == false then
									table.insert(candidates, {nx, ny, nidx});
								end
							end
						end
						dIndex = dIndex + 1;
					end
					pIndex = pIndex + 1;
				end
				local nCands = #candidates;
				if nCands < 1 then
					break
				end
				local pick = candidates[Map.Rand(nCands, "Oasis Crescent Grow") + 1];
				if plotTypes[pick[3]] ~= PlotTypes.PLOT_OCEAN then
					plotTypes[pick[3]] = PlotTypes.PLOT_OCEAN;
					blobSet[pick[3]] = true;
					nPaint = nPaint + 1;
					grown = grown + 1;
				end
				table.insert(blob, {pick[1], pick[2]});
			end
		end
		b = b + 1;
	end
	print("Oasis crescent seas: bodies=", nOk, "/", nBodies, " tiles=", nPaint);
end
------------------------------------------------------------------------------
function WaterAllowedAtX(x)
	local iW = Map.GetGridSize();
	local wrapN, centerN = ResolveSnowWrapWidths();
	local wrapHalf = wrapN / 2;
	local centerHalf = centerN / 2;
	local mid = math.floor(iW / 2);
	if wrapHalf > 0 then
		if x <= (wrapHalf + 3) then
			return false
		end
		if x >= (iW - wrapHalf - 4) then
			return false
		end
	end
	if IsOasisClimate() then
		local hinter = OasisWestDesertColumns();
		if x < hinter or x >= (iW - hinter) then
			return false
		end
	end
	if centerHalf > 0 and IsTiltedMirrorAxis() == false then
		if x >= (mid - centerHalf - 4) and x <= (mid + centerHalf - 1 + 4) then
			return false
		end
	end
	return true
end
------------------------------------------------------------------------------
function WaterAllowedAtXY(x, y)
	if WaterAllowedAtX(x) == false then
		return false
	end
	if IsTiltedMirrorAxis() then
		local wx, wy = TiltedFoldWest(x, y);
		local lim = TongueHillDist();
		if IsBramble() then
			-- Min 7 tiles clear of the separator's actual edge, everywhere --
			-- using the widest possible strip (7 wide, half-width 4) as the
			-- buffer so the true distance-to-tundra is never less than 7,
			-- even where the noisy strip happens to be at its widest.
			lim = 4 + 7;
		else
			-- Standard-Diagonal: keep water at least 7 tiles clear of the
			-- barrier band's own edge (not just the bare fold line) -- this
			-- inherited Tongue's ~1-tile gap, far tighter than intended here.
			local _, centerN = ResolveSnowWrapWidths();
			lim = math.floor(centerN / 2) + 7;
		end
		if TiltedSignedDist(wx, wy) <= lim then
			return false
		end
	end
	return true
end
------------------------------------------------------------------------------
function EnsureLandNotSplitByOcean()
	return
end
------------------------------------------------------------------------------
function ScrubWaterNearSnow_UNUSED()
	do return end
	local iW, iH = Map.GetGridSize();
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local n = 0;
	local x0 = 0;
	local x1 = iW - 1;
	local bandPass = 1;
	local nPass = 1;
	if DEF_MIRRORED == 1 then
		nPass = 2;
	end
	while bandPass <= nPass do
		if DEF_MIRRORED == 1 then
			local mid = math.floor(iW / 2);
			if bandPass == 1 then
				x0 = 0;
				x1 = mid - 1;
			else
				x0 = mid;
				x1 = iW - 1;
			end
		end
		local filled = 1;
		local fillGuard = 0;
		while filled > 0 and fillGuard < 8 do
			fillGuard = fillGuard + 1;
			filled = 0;
			local comp = {};
			local nComp = 0;
			local y = 0;
			while y < iH do
				local x = x0;
				while x <= x1 do
					local plot = Map.GetPlot(x, y);
					local k = y * iW + x;
					if plot ~= nil and plot:GetPlotType() ~= PlotTypes.PLOT_OCEAN and comp[k] == nil then
						nComp = nComp + 1;
						local id = nComp;
						local qx = {x};
						local qy = {y};
						comp[k] = id;
						local qi = 1;
						while qi <= #qx do
							local dirs = evenN;
							if qy[qi] % 2 == 1 then
								dirs = oddN;
							end
							local d = 1;
							while d <= 6 do
								local nx = qx[qi] + dirs[d][1];
								local ny = qy[qi] + dirs[d][2];
								if ny >= 0 and ny < iH and nx >= x0 and nx <= x1 then
									local nk = ny * iW + nx;
									if comp[nk] == nil then
										local np = Map.GetPlot(nx, ny);
										if np ~= nil and np:GetPlotType() ~= PlotTypes.PLOT_OCEAN then
											comp[nk] = id;
											table.insert(qx, nx);
											table.insert(qy, ny);
										end
									end
								end
								d = d + 1;
							end
							qi = qi + 1;
						end
					end
					x = x + 1;
				end
				y = y + 1;
			end
			y = 0;
			while y < iH do
				local x = x0;
				while x <= x1 do
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
						local seen = {};
						local nAdj = 0;
						local dirs = evenN;
						if y % 2 == 1 then
							dirs = oddN;
						end
						local d = 1;
						while d <= 6 do
							local nx = x + dirs[d][1];
							local ny = y + dirs[d][2];
							if ny >= 0 and ny < iH and nx >= x0 and nx <= x1 then
								local cid = comp[ny * iW + nx];
								if cid ~= nil and seen[cid] ~= true then
									seen[cid] = true;
									nAdj = nAdj + 1;
								end
							end
							d = d + 1;
						end
						if nAdj >= 2 then
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
							filled = filled + 1;
						end
					end
					x = x + 1;
				end
				y = y + 1;
			end
		end
		local comp = {};
		local sizes = {};
		local playSizes = {};
		local nComp = 0;
		local y = 0;
		while y < iH do
			local x = x0;
			while x <= x1 do
				local plot = Map.GetPlot(x, y);
				local k = y * iW + x;
				if plot ~= nil and plot:GetPlotType() ~= PlotTypes.PLOT_OCEAN and comp[k] == nil then
					nComp = nComp + 1;
					local id = nComp;
					local qx = {x};
					local qy = {y};
					comp[k] = id;
					local nTiles = 1;
					local nPlay = 0;
					if OasisIsWestHinterlandX(x, iW) == false then
						nPlay = 1;
					end
					local qi = 1;
					while qi <= #qx do
						local dirs = evenN;
						if qy[qi] % 2 == 1 then
							dirs = oddN;
						end
						local d = 1;
						while d <= 6 do
							local nx = qx[qi] + dirs[d][1];
							local ny = qy[qi] + dirs[d][2];
							if ny >= 0 and ny < iH and nx >= x0 and nx <= x1 then
								local nk = ny * iW + nx;
								if comp[nk] == nil then
									local np = Map.GetPlot(nx, ny);
									if np ~= nil and np:GetPlotType() ~= PlotTypes.PLOT_OCEAN then
										comp[nk] = id;
										table.insert(qx, nx);
										table.insert(qy, ny);
										nTiles = nTiles + 1;
										if OasisIsWestHinterlandX(nx, iW) == false then
											nPlay = nPlay + 1;
										end
									end
								end
							end
							d = d + 1;
						end
						qi = qi + 1;
					end
					sizes[id] = nTiles;
					playSizes[id] = nPlay;
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local keep = 1;
		local bestPlay = -1;
		local best = 0;
		local id = 1;
		while id <= nComp do
			local ps = playSizes[id];
			local ts = sizes[id];
			if ps == nil then
				ps = 0;
			end
			if ts == nil then
				ts = 0;
			end
			if ps > bestPlay or (ps == bestPlay and ts > best) then
				bestPlay = ps;
				best = ts;
				keep = id;
			end
			id = id + 1;
		end
		y = 0;
		while y < iH do
			local x = x0;
			while x <= x1 do
				local k = y * iW + x;
				if comp[k] ~= nil and comp[k] ~= keep then
					if OasisIsWestHinterlandX(x, iW) == false then
						local p = Map.GetPlot(x, y);
						p:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
						p:SetTerrainType(TerrainTypes.TERRAIN_OCEAN, false, false);
						p:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						n = n + 1;
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		bandPass = bandPass + 1;
	end
	if n > 0 then
		GenerateCoasts({bExpandCoasts = false});
		Map.CalculateAreas();
	end
	print("Split land cleared:", n);
	WeeveeDbg("EnsureLandNotSplitByOcean done n=" .. tostring(n));
end
------------------------------------------------------------------------------
function ScrubWaterNearSnow()
	if IsSnowBarrier() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if WaterAllowedAtXY(x, y) == false then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function GetSnowWrapColumns(iW, y)
	local cols = {};
	local wrapN, centerN = ResolveSnowWrapWidths();
	if wrapN > 0 then
		local half = wrapN / 2;
		for x = 0, half - 1 do
			table.insert(cols, x);
		end
		for x = iW - half, iW - 1 do
			table.insert(cols, x);
		end
	end
	if centerN > 0 and IsBramble() == false then
		local half = centerN / 2;
		local mid = math.floor(iW / 2);
		if IsTiltedMirrorAxis() and y ~= nil then
			mid = TiltedFoldMid(y);
		end
		for x = mid - half, mid + half - 1 do
			table.insert(cols, x);
		end
	end
	return cols;
end
------------------------------------------------------------------------------
function GetSnowWrapTundraColumns(iW, y)
	local cols = {};
	local wrapN, centerN = ResolveSnowWrapWidths();
	local mid = math.floor(iW / 2);
	if IsTiltedMirrorAxis() and y ~= nil then
		mid = TiltedFoldMid(y);
	end
	if wrapN > 0 then
		local half = wrapN / 2;
		table.insert(cols, half);
		table.insert(cols, iW - half - 1);
	end
	if centerN > 0 and IsBramble() == false then
		local half = centerN / 2;
		table.insert(cols, mid - half - 1);
		table.insert(cols, mid + half);
	end
	return cols;
end
------------------------------------------------------------------------------
function GetSnowWrapLandMountainXs(iW)
	local wrapN = ResolveSnowWrapWidths();
	local wrapHalf = wrapN / 2;
	local firstLand = wrapHalf + 1;
	local xWest = 3;
	if xWest < firstLand then
		xWest = firstLand;
	end
	return xWest, iW - 1 - xWest;
end
------------------------------------------------------------------------------
function PlaceMirroredMountain(plotTypes, iW, iH, x, y)
	if x < 0 or x >= iW or y < 0 or y >= iH then
		return false
	end
	local idx = y * iW + x + 1;
	if plotTypes[idx] == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	plotTypes[idx] = PlotTypes.PLOT_MOUNTAIN;
	local mx = iW - x - 1;
	local my = iH - y - 1;
	plotTypes[my * iW + mx + 1] = PlotTypes.PLOT_MOUNTAIN;
	return true
end
------------------------------------------------------------------------------
function HexDirsForY(y)
	if y % 2 ~= 0 then
		return {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	end
	return {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
end
------------------------------------------------------------------------------
-- Restored 2026-09-16: accidentally deleted along with the old Snaky
-- cluster it happened to sit inside (it was a shared utility, not a
-- Snaky-specific function -- ForestMountainsToBareTarget still calls it).
-- Its absence didn't error visibly: calling a nil global inside the map
-- generation Lua context silently aborts generation without reaching
-- StartPlotSystem, instead of surfacing in Lua.log the way a UI-script
-- error would -- symptom was every climate showing "no valid start" on
-- load whenever ForestMountainsToBareTarget's forest branch ran.
function HexNearFeature(x, y, feat, maxd)
	local yy = y - maxd;
	while yy <= y + maxd do
		local xx = x - maxd;
		while xx <= x + maxd do
			if Map.PlotDistance(x, y, xx, yy) <= maxd then
				local p = Map.GetPlot(xx, yy);
				if p ~= nil and p:GetFeatureType() == feat then
					return true
				end
			end
			xx = xx + 1;
		end
		yy = yy + 1;
	end
	return false
end
------------------------------------------------------------------------------
-- Size of the contiguous mountain blob touching (x,y) (hex-adjacency),
-- counting any pre-existing mountains it connects to. Stops early past
-- cap since callers only care whether it's exceeded.
function MountainClumpSize(plotTypes, iW, iH, x, y, cap)
	local visited = {};
	local qx, qy = {x}, {y};
	visited[y * iW + x] = true;
	local count = 0;
	local qi = 1;
	while qi <= #qx do
		local px, py = qx[qi], qy[qi];
		qi = qi + 1;
		count = count + 1;
		if count > cap then
			return count;
		end
		local dirs = HexDirsForY(py);
		local d = 1;
		while d <= 6 do
			local nx, ny = px + dirs[d][1], py + dirs[d][2];
			if nx >= 0 and nx < iW and ny >= 0 and ny < iH then
				local nk = ny * iW + nx;
				if visited[nk] ~= true and plotTypes[ny * iW + nx + 1] == PlotTypes.PLOT_MOUNTAIN then
					visited[nk] = true;
					qx[#qx + 1] = nx;
					qy[#qy + 1] = ny;
				end
			end
			d = d + 1;
		end
	end
	return count;
end
------------------------------------------------------------------------------
-- Like PlaceMirroredMountain, but rejects (and reverts) the placement if it
-- would grow either side's mountain blob past cap -- including merging
-- into mountains already placed by the normal (non-front) terrain pass.
function PlaceMirroredMountainCapped(plotTypes, iW, iH, x, y, cap)
	if x < 0 or x >= iW or y < 0 or y >= iH then
		return false
	end
	local idx = y * iW + x + 1;
	if plotTypes[idx] == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	local mx, my = iW - x - 1, iH - y - 1;
	local midx = my * iW + mx + 1;
	local prevA, prevB = plotTypes[idx], plotTypes[midx];
	plotTypes[idx] = PlotTypes.PLOT_MOUNTAIN;
	plotTypes[midx] = PlotTypes.PLOT_MOUNTAIN;
	if MountainClumpSize(plotTypes, iW, iH, x, y, cap) > cap or MountainClumpSize(plotTypes, iW, iH, mx, my, cap) > cap then
		plotTypes[idx] = prevA;
		plotTypes[midx] = prevB;
		return false
	end
	return true
end
------------------------------------------------------------------------------
-- Column-weighted front ridge design: mountains sit only on the barrier's
-- transition column and the two columns beyond it, weighted toward the
-- middle one (col2), in a handful of short ridges instead of a
-- continuous scattered band. West side only; PlaceMirroredMountain
-- handles the east side automatically.
-- Five positions instead of three: col1 is the transition column itself
-- (matches GetSnowWrapTundraColumns' mid - half - 1), col2-col5 step
-- further west from there. Only col1-col3 get purged clean of tectonics
-- mountains (see PurgeFrontMountainColumns); col4/col5 are placed into
-- on top of whatever tectonics already left there, by design.
function GetFrontMountainColumns5West(iW)
	local wrapN, centerN = ResolveSnowWrapWidths();
	local half = centerN / 2;
	local mid = math.floor(iW / 2);
	return mid - half - 1, mid - half - 2, mid - half - 3, mid - half - 4, mid - half - 5;
end
function GetFrontMountainColumnsWest(iW)
	local col1, col2, col3 = GetFrontMountainColumns5West(iW);
	return col1, col2, col3;
end
------------------------------------------------------------------------------
-- Same five positions, but as offsets from TiltedFoldMid(y) instead of a
-- fixed column, for climates whose barrier runs along the diagonal fold
-- (Standard-Diagonal). Pass these to PlaceFrontMountainField with
-- tilted=true.
function GetFrontMountainOffsets5West()
	local wrapN, centerN = ResolveSnowWrapWidths();
	local half = centerN / 2;
	return -(half + 1), -(half + 2), -(half + 3), -(half + 4), -(half + 5);
end
function GetFrontMountainOffsetsWest()
	local off1, off2, off3 = GetFrontMountainOffsets5West();
	return off1, off2, off3;
end
------------------------------------------------------------------------------
-- Demotes every mountain in the front's 3-column zone (col1/col2/col3, or
-- their tilted fold offsets) back to hills, on both the given tile and its
-- 180-rotation mirror -- ApplyTectonics itself is not mirror-symmetric, so
-- both sides need clearing explicitly. Used to strip whatever the normal
-- terrain pass seeded there before PlaceFrontMountainField builds on top
-- of a clean slate (see DISABLE_FRONT_MOUNTAIN_RIDGES for isolating this).
function PurgeFrontMountainColumns(plotTypes, iW, iH, col1, col2, col3, tilted)
	local cols = {col1, col2, col3};
	for y = 1, iH - 2 do
		local ci = 1;
		while ci <= 3 do
			local x = cols[ci];
			if tilted then
				x = TiltedFoldMid(y) + cols[ci];
			end
			if x >= 0 and x < iW then
				local idx = y * iW + x + 1;
				if plotTypes[idx] == PlotTypes.PLOT_MOUNTAIN then
					plotTypes[idx] = PlotTypes.PLOT_HILLS;
				end
				local mx, my = iW - x - 1, iH - y - 1;
				local midx = my * iW + mx + 1;
				if plotTypes[midx] == PlotTypes.PLOT_MOUNTAIN then
					plotTypes[midx] = PlotTypes.PLOT_HILLS;
				end
			end
			ci = ci + 1;
		end
	end
end
------------------------------------------------------------------------------
-- Ground-up front mountain field, used by every non-WIP climate's front
-- (Standard, Standard-Diagonal, Murky, Oasis, Peaky -- Frosty/Slate/
-- Wasteland stay on the old chaotic-ridge/fallback systems). Rules, in
-- priority order:
--   1. Mountains are placed across all 5 front columns (col1-col5).
--   2. Exactly one deliberate "opening" -- a run of 4-6 consecutive rows
--      with zero mountains across all 5 columns -- guarantees a real pass
--      through the front.
--   3. Outside that opening, no run of 7+ consecutive rows is ever left
--      without a mountain (a random 1-6 row threshold, re-rolled after each
--      forced mountain, keeps the spacing irregular but always <= 6).
--   4. Whatever budget is left after satisfying 2/3 is scattered at random
--      rows/columns (never inside the opening) for a high-noise field.
-- col1-col5 are absolute columns, unless tilted=true, in which case they're
-- offsets from TiltedFoldMid(y) (see GetFrontMountainOffsets5West) and get
-- re-resolved to an absolute x every row, so the field tracks the diagonal
-- barrier instead of cutting straight through it.
function PlaceFrontMountainField(plotTypes, iW, iH, col1, col2, col3, col4, col5, budget, clumpCap, tilted)
	if budget < 1 then
		return
	end
	local cols = {col1, col2, col3, col4, col5};
	local yLo, yHi = 1, iH - 2;
	local span = yHi - yLo + 1;
	if span < 1 then
		return
	end

	local openLen = 4 + Map.Rand(3, "Front Opening Length"); -- 4, 5 or 6
	if openLen > span then
		openLen = span;
	end
	local openStart = yLo + Map.Rand(span - openLen + 1, "Front Opening Start");
	local openEnd = openStart + openLen - 1;
	table.insert(frontMountainZones, {cols = cols, tilted = tilted, openStart = openStart, openEnd = openEnd});

	local function resolveX(col, y)
		if tilted then
			return TiltedFoldMid(y) + col;
		end
		return col;
	end

	-- Tries the 5 columns at row y in random order (falling through on a
	-- clump-cap rejection) and places on the first that succeeds.
	local function tryPlaceAt(y)
		local order = GetShuffledCopyOfTable({1, 2, 3, 4, 5});
		local k = 1;
		while k <= 5 do
			local x = resolveX(cols[order[k]], y);
			if PlaceMirroredMountainCapped(plotTypes, iW, iH, x, y, clumpCap) then
				return true;
			end
			k = k + 1;
		end
		return false;
	end

	-- Backbone pass: guarantees rules 2 and 3 first, since they're
	-- structural, before any budget is spent on random noise.
	local remaining = budget;
	local sinceMountain = 0;
	local threshold = 1 + Map.Rand(6, "Front Backbone Gap");
	local y = yLo;
	while y <= yHi and remaining > 0 do
		local inOpening = (y >= openStart and y <= openEnd);
		local mustForce = false;
		if not inOpening then
			sinceMountain = sinceMountain + 1;
			if sinceMountain > threshold then
				mustForce = true;
			end
		end
		-- Pin the row just outside each end of the opening too, so the
		-- mountain-free run can't drift wider than openLen by merging with
		-- whatever gap happens to sit next to it.
		if y == openStart - 1 or y == openEnd + 1 then
			mustForce = true;
		end
		if mustForce and not inOpening then
			if tryPlaceAt(y) then
				remaining = remaining - 1;
				sinceMountain = 0;
				threshold = 1 + Map.Rand(6, "Front Backbone Gap");
			end
		end
		y = y + 1;
	end

	-- Noise pass: whatever budget remains is scattered at random rows
	-- (excluding the opening) for the high-random, high-noise look.
	local noiseRows = {};
	for ny = yLo, yHi do
		if ny < openStart or ny > openEnd then
			table.insert(noiseRows, ny);
		end
	end
	local shuffledRows = GetShuffledCopyOfTable(noiseRows);
	local ri = 1;
	while remaining > 0 and ri <= #shuffledRows do
		if tryPlaceAt(shuffledRows[ri]) then
			remaining = remaining - 1;
		end
		ri = ri + 1;
	end
end
------------------------------------------------------------------------------
-- Live-map (Map.GetPlot, not the plotTypes array) equivalent of
-- MountainClumpSize, for use after GeneratePlotTypes has finished and the
-- temporary plotTypes array is gone.
function LiveMountainClumpSize(x, y, cap)
	local iW, iH = Map.GetGridSize();
	local visited = {};
	local qx, qy = {x}, {y};
	visited[y * iW + x] = true;
	local count = 0;
	local qi = 1;
	while qi <= #qx do
		local px, py = qx[qi], qy[qi];
		qi = qi + 1;
		count = count + 1;
		if count > cap then
			return count;
		end
		local dirs = HexDirsForY(py);
		local d = 1;
		while d <= 6 do
			local nx, ny = px + dirs[d][1], py + dirs[d][2];
			if nx >= 0 and nx < iW and ny >= 0 and ny < iH then
				local nk = ny * iW + nx;
				if visited[nk] ~= true then
					local p = Map.GetPlot(nx, ny);
					if p ~= nil and p:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						visited[nk] = true;
						qx[#qx + 1] = nx;
						qy[#qy + 1] = ny;
					end
				end
			end
			d = d + 1;
		end
	end
	return count;
end
------------------------------------------------------------------------------
function TryPatchFrontMountainGap(x, y, cap)
	if x < 0 or x >= Map.GetGridSize() then
		return false
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil or plot:IsWater() or plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN or PlotHasNaturalWonder(plot) then
		return false
	end
	local prevType = plot:GetPlotType();
	plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
	if LiveMountainClumpSize(x, y, cap) > cap then
		plot:SetPlotType(prevType, false, false);
		return false
	end
	return true
end
------------------------------------------------------------------------------
-- Post-wonder safety net for PlaceFrontMountainField's rule 3 (no 7+ row
-- gap with zero mountains). Natural Wonders can land in columns 4-5 (the
-- two columns deliberately left un-purged, contaminated by tectonics) after
-- generation already committed to a mountain layout -- they're never
-- touched or demoted, but they DO count as an obstacle here, the same as a
-- mountain would, since most Natural Wonders are impassable. Must run after
-- PlaceNaturalWonders and before MirrorPlotsAfterResourcePlacement -- west
-- side only, the mirror copy carries any patch over to east automatically.
function AuditFrontMountainGaps()
	local iW, iH = Map.GetGridSize();
	local yLo, yHi = 1, iH - 2;
	local zi = 1;
	while zi <= #frontMountainZones do
		local zone = frontMountainZones[zi];
		local cols = zone.cols;
		local gapStart = nil;
		local y = yLo;
		while y <= yHi + 1 do
			local inOpening = (y >= zone.openStart and y <= zone.openEnd);
			local occupied = false;
			if y <= yHi and not inOpening then
				local ci = 1;
				while ci <= 5 do
					local x = cols[ci];
					if zone.tilted then
						x = TiltedFoldMid(y) + cols[ci];
					end
					if x >= 0 and x < iW then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil then
							if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
								occupied = true;
							elseif (ci == 4 or ci == 5) and PlotHasNaturalWonder(plot) then
								occupied = true;
							end
						end
					end
					ci = ci + 1;
				end
			end
			if y > yHi or inOpening or occupied then
				if gapStart ~= nil then
					local gapEnd = y - 1;
					if (gapEnd - gapStart + 1) >= 7 then
						local midY = gapStart + math.floor((gapEnd - gapStart) / 2);
						local patched = false;
						local dy = 0;
						while patched == false and dy <= (gapEnd - gapStart) do
							local tries = {midY + dy, midY - dy};
							local ti = 1;
							while ti <= 2 and patched == false do
								local py = tries[ti];
								if py >= gapStart and py <= gapEnd then
									local order = GetShuffledCopyOfTable({1, 2, 3});
									local ci2 = 1;
									while ci2 <= 3 and patched == false do
										local x = cols[order[ci2]];
										if zone.tilted then
											x = TiltedFoldMid(py) + cols[order[ci2]];
										end
										patched = TryPatchFrontMountainGap(x, py, FRONT_MOUNTAIN_CLUMP_CAP);
										ci2 = ci2 + 1;
									end
								end
								ti = ti + 1;
							end
							dy = dy + 1;
						end
						if patched == false then
							WeeveeDbg("AuditFrontMountainGaps: could not patch gap rows " .. gapStart .. "-" .. gapEnd);
						end
					end
				end
				gapStart = nil;
			else
				if gapStart == nil then
					gapStart = y;
				end
			end
			y = y + 1;
		end
		zi = zi + 1;
	end
end
------------------------------------------------------------------------------
function PlaceChaoticFrontRidge(plotTypes, iW, iH, xCenter, density)
	local xMin = xCenter - 2;
	local xMax = xCenter + 2;
	if xMin < 0 then
		xMin = 0;
	end
	local mid = math.floor(iW / 2);
	if xMax >= mid then
		xMax = mid - 1;
	end
	local target = math.floor(iH * density);
	if target < 1 then
		target = 1;
	end
	local x = xCenter;
	local y = Map.Rand(iH, "Chaotic Ridge StartY");
	local placed = 0;
	local steps = 0;
	local maxSteps = iH * 10;
	if maxSteps < 40 then
		maxSteps = 40;
	end
	while placed < target and steps < maxSteps do
		steps = steps + 1;
		if PlaceMirroredMountain(plotTypes, iW, iH, x, y) then
			placed = placed + 1;
		end
		if placed < target and Map.Rand(10, "Chaotic Spur") < 5 then
			local sx = x + (Map.Rand(3, "Chaotic SpurX") - 1);
			local sy = y + (Map.Rand(3, "Chaotic SpurY") - 1);
			if sx < xMin then
				sx = xMin;
			end
			if sx > xMax then
				sx = xMax;
			end
			if sy < 0 then
				sy = 0;
			end
			if sy >= iH then
				sy = iH - 1;
			end
			if PlaceMirroredMountain(plotTypes, iW, iH, sx, sy) then
				placed = placed + 1;
			end
		end
		local dy = Map.Rand(3, "Chaotic WalkY") - 1;
		if dy == 0 then
			if Map.Rand(2, "Chaotic WalkY2") == 0 then
				dy = 1;
			else
				dy = -1;
			end
		end
		if Map.Rand(4, "Chaotic Skip") == 0 then
			dy = dy + dy;
		end
		y = y + dy;
		if y < 0 then
			y = 0;
		end
		if y >= iH then
			y = iH - 1;
		end
		x = x + (Map.Rand(3, "Chaotic WalkX") - 1);
		if x < xMin then
			x = xMin;
		end
		if x > xMax then
			x = xMax;
		end
	end
end
------------------------------------------------------------------------------
function FillOasisWestNoOcean(plotTypes, iW, iH)
	if plotTypes == nil or IsOasisClimate() == false then
		return
	end
	local band = OasisWestDesertColumns();
	local mid = math.floor(iW / 2) - 1;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < band and x <= mid do
			if plotTypes[y * iW + x + 1] == PlotTypes.PLOT_OCEAN then
				plotTypes[y * iW + x + 1] = PlotTypes.PLOT_LAND;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x < band do
			local mx = iW - x - 1;
			local my = iH - y - 1;
			plotTypes[my * iW + mx + 1] = plotTypes[y * iW + x + 1];
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function ShapeNoWrapBackstrip(plotTypes, iW, iH)
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local minD = 2;
	local maxD = 3;
	local depth = 2;
	local nIslands = 3 + Map.Rand(3, "NoWrap Back Islands");
	local frostyCfg = GetBarrierConfig();
	local isFrosty = frostyCfg ~= nil and frostyCfg.kind == "frosty";
	-- Peaky claims a much deeper (more horizontal) back coast than the
	-- default 3-column strip -- combined with ResolveSaltWaterPlan's own
	-- peaks branch (cutPct, and anchoring the kept vertical window to a
	-- corner), the two together roughly triple the blob's surface area
	-- versus the original narrower/shallower version, while keeping both
	-- dimensions randomized per roll rather than pinning one fixed
	-- size/shape. Actual islands are no longer placed here at all: they're
	-- carved by AddPeaksBackCoastIslands once terrain has settled, since
	-- AddPeaksLayout's own land-flatten pass (which runs after this, during
	-- GenerateTerrain) would otherwise wipe anything placed at the
	-- plotTypes-array stage right back to flat land.
	local isPeaks = frostyCfg ~= nil and frostyCfg.kind == "peaks";
	local backMax = isPeaks and 8 or 2;
	if UsesExploCoastShape() then
		minD = 1;
		maxD = 2;
		depth = 1;
		nIslands = 1 + Map.Rand(2, "NoWrap Back Islands");
		if isFrosty then
			minD = 2;
			maxD = 3;
			depth = 2;
		elseif isPeaks then
			minD = 3;
			maxD = 7;
			depth = 5;
			nIslands = 0;
		end
	end
	local y = 0;
	while y < iH do
		local step = Map.Rand(3, "NoWrap Coast Walk") - 1;
		depth = depth + step;
		if depth < minD then
			depth = minD;
		end
		if depth > maxD then
			depth = maxD;
		end
		local x = 0;
		while x <= backMax do
			local i = y * iW + x + 1;
			if x < depth then
				plotTypes[i] = PlotTypes.PLOT_OCEAN;
			elseif x <= backMax - 1 then
				plotTypes[i] = PlotTypes.PLOT_LAND;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local cutPct = ResolveExploBackCoastPlan();
	local winY0 = 0;
	local winY1 = iH;
	if cutPct > 0 then
		local keepH = math.floor(iH * (100 - cutPct) / 100);
		if keepH < 4 then
			keepH = 4;
		end
		if keepH > iH then
			keepH = iH;
		end
		if frostyCfg ~= nil and frostyCfg.kind == "frosty" then
			winY0 = iH - keepH;
			winY1 = iH;
		elseif isPeaks then
			-- Anchored to a north or south corner rather than floating
			-- anywhere along the height -- a "west, north or south corner"
			-- blob instead of a strip that could land centered on the coast.
			if Map.Rand(2, "Peaks BackCoast Corner") == 0 then
				winY0 = 0;
				winY1 = keepH;
			else
				winY0 = iH - keepH;
				winY1 = iH;
			end
		else
			if iH > keepH then
				winY0 = Map.Rand(iH - keepH + 1, "Explo back coast window");
			end
			winY1 = winY0 + keepH;
		end
	end
	if winY0 > 0 or winY1 < iH then
		y = 0;
		while y < iH do
			if y < winY0 or y >= winY1 then
				local x = 0;
				while x <= backMax do
					plotTypes[y * iW + x + 1] = PlotTypes.PLOT_LAND;
					x = x + 1;
				end
			end
			y = y + 1;
		end
	end
	local placed = 0;
	local attempts = 0;
	while placed < nIslands and attempts < 90 do
		attempts = attempts + 1;
		local ySpan = iH - 2;
		if ySpan < 1 then
			ySpan = 1;
		end
		local iy = 1 + Map.Rand(ySpan, "NoWrap Island Y");
		local ix = 1;
		local i = iy * iW + ix + 1;
		if plotTypes[i] == PlotTypes.PLOT_OCEAN then
			local adjMainland = false;
			local dirs = evenN;
			if iy % 2 == 1 then
				dirs = oddN;
			end
			local d = 1;
			while d <= 6 do
				local nx = ix + dirs[d][1];
				local ny = iy + dirs[d][2];
				if ny >= 0 and ny < iH and nx >= 0 and nx < iW then
					if plotTypes[ny * iW + nx + 1] ~= PlotTypes.PLOT_OCEAN then
						if nx >= 2 then
							adjMainland = true;
						end
					end
				end
				d = d + 1;
			end
			if adjMainland == false then
				if Map.Rand(3, "NoWrap Island Hills") == 0 then
					plotTypes[i] = PlotTypes.PLOT_HILLS;
				else
					plotTypes[i] = PlotTypes.PLOT_LAND;
				end
				placed = placed + 1;
				if Map.Rand(2, "NoWrap Island Pair") == 0 then
					local pd = 1 + Map.Rand(6, "NoWrap Island PairDir");
					local px = ix + dirs[pd][1];
					local py = iy + dirs[pd][2];
					if py >= 1 and py < iH - 1 and px == 1 then
						local pi = py * iW + px + 1;
						if plotTypes[pi] == PlotTypes.PLOT_OCEAN then
							local pairMainland = false;
							local pdirs = evenN;
							if py % 2 == 1 then
								pdirs = oddN;
							end
							local e = 1;
							while e <= 6 do
								local ex = px + pdirs[e][1];
								local ey = py + pdirs[e][2];
								if ey >= 0 and ey < iH and ex >= 0 and ex < iW then
									if plotTypes[ey * iW + ex + 1] ~= PlotTypes.PLOT_OCEAN then
										if ex >= 2 then
											pairMainland = true;
										end
									end
								end
								e = e + 1;
							end
							if pairMainland == false then
								plotTypes[pi] = plotTypes[i];
							end
						end
					end
				end
			end
		end
	end
	y = 0;
	while y < iH do
		if y >= winY0 and y < winY1 then
			plotTypes[y * iW + 1] = PlotTypes.PLOT_OCEAN;
		end
		y = y + 1;
	end
	if isFrosty then
		local fromNorth = 3 + Map.Rand(4, "Frosty Fjord FromNorth");
		local fy = (iH - 1) - fromNorth;
		if fy < 1 then
			fy = 1;
		end
		if fy > iH - 2 then
			fy = iH - 2;
		end
		local yMin = (iH - 1) - 7;
		if yMin < 1 then
			yMin = 1;
		end
		local maxX = math.floor(iW / 2) - 6;
		if maxX < 6 then
			maxX = 6;
		end
		local len = 5 + Map.Rand(5, "Frosty Fjord Len");
		local fx = 0;
		local step = 0;
		while step < len and fx <= maxX do
			plotTypes[fy * iW + fx + 1] = PlotTypes.PLOT_OCEAN;
			local mx = iW - fx - 1;
			local my = iH - fy - 1;
			plotTypes[my * iW + mx + 1] = PlotTypes.PLOT_OCEAN;
			if Map.Rand(3, "Frosty Fjord Wide") == 0 then
				local wy = fy + 1;
				if wy < iH then
					plotTypes[wy * iW + fx + 1] = PlotTypes.PLOT_OCEAN;
					plotTypes[(iH - wy - 1) * iW + (iW - fx - 1) + 1] = PlotTypes.PLOT_OCEAN;
				end
			end
			fx = fx + 1;
			if Map.Rand(3, "Frosty Fjord Meander") == 0 then
				if Map.Rand(2, "Frosty Fjord DY") == 0 then
					fy = fy + 1;
				else
					fy = fy - 1;
				end
				if fy < yMin then
					fy = yMin;
				end
				if fy > iH - 2 then
					fy = iH - 2;
				end
			end
			step = step + 1;
		end
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x <= math.max(backMax, 3) do
			local mx = iW - x - 1;
			local my = iH - y - 1;
			plotTypes[my * iW + mx + 1] = plotTypes[y * iW + x + 1];
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Standard-Diagonal's water, built from scratch against a measured reference
-- (Murky's own salt water averaged ~7.6% of its map across 13 rolls). Runs
-- entirely on the plotTypes array (pre-Map-commit), same as the functions
-- above. Spec agreed with the user:
--   ~8% of the map in salt water (natural variance, like Murky's own spread).
--   50% of maps: all of that budget as one continuous back (west) coast.
--   25%: 1 inland sea; 25%: 2 inland seas -- each sized 4-10 tiles and
--     deducted from the 8% budget before the back coast gets what's left.
--   The back coast gets one deliberately "thick" pocket sized for a big
--     island (5-15 tiles), plus 0-6 small islands (1-4 tiles) elsewhere.
--   Islands force-carve their own 1-tile moat rather than relying on enough
--     open water already being there -- simpler and can't silently fail.
-- Also used by Bramble (removed from its exclusion list) -- the ~8%
-- salt-water target and 50/25/25 back-coast/1-inland/2-inland split match
-- what the user asked for ("similar amount of water as murky/standard...
-- several small inland seas or no inland seas, all back coast fine").
function PlaceDiagonalBackWater(plotTypes, iW, iH)
	if plotTypes == nil or IsTiltedMirrorAxis() == false then
		return
	end
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local function neighborDirs(y)
		if y % 2 == 0 then
			return evenN;
		end
		return oddN;
	end
	local function setPlot(x, y, pt)
		if x < 0 or x >= iW or y < 0 or y >= iH then
			return
		end
		plotTypes[y * iW + x + 1] = pt;
		local mx = iW - x - 1;
		local my = iH - y - 1;
		plotTypes[my * iW + mx + 1] = pt;
	end
	local function getPlot(x, y)
		if x < 0 or x >= iW or y < 0 or y >= iH then
			return nil
		end
		return plotTypes[y * iW + x + 1];
	end
	local function inBlob(blob, x, y)
		local bi = 1;
		while bi <= #blob do
			if blob[bi][1] == x and blob[bi][2] == y then
				return true
			end
			bi = bi + 1;
		end
		return false
	end
	-- Grows into open water only (for inland seas): stops at land/mountains,
	-- ownership and the barrier's front-distance buffer.
	local function growWater(seedX, seedY, size, allowedFn)
		local blob = {{seedX, seedY}};
		setPlot(seedX, seedY, PlotTypes.PLOT_OCEAN);
		while #blob < size do
			local candidates = {};
			local bi = 1;
			while bi <= #blob do
				local p = blob[bi];
				local dirs = neighborDirs(p[2]);
				local d = 1;
				while d <= 6 do
					local nx = p[1] + dirs[d][1];
					local ny = p[2] + dirs[d][2];
					if nx >= 0 and nx < iW and ny >= 0 and ny < iH and getPlot(nx, ny) ~= PlotTypes.PLOT_OCEAN and allowedFn(nx, ny) then
						table.insert(candidates, {nx, ny});
					end
					d = d + 1;
				end
				bi = bi + 1;
			end
			if #candidates < 1 then
				break
			end
			local pick = candidates[Map.Rand(#candidates, "DiagWater Sea Grow") + 1];
			setPlot(pick[1], pick[2], PlotTypes.PLOT_OCEAN);
			table.insert(blob, pick);
		end
		return blob;
	end
	-- Forces land regardless of what's currently there -- used for islands,
	-- which then get their own moat carved rather than needing to find
	-- naturally-open water already the right shape.
	local function forceGrowLand(seedX, seedY, size)
		local blob = {{seedX, seedY}};
		local function paintOne(x, y)
			if Map.Rand(4, "DiagWater Island Hills") == 0 then
				setPlot(x, y, PlotTypes.PLOT_HILLS);
			else
				setPlot(x, y, PlotTypes.PLOT_LAND);
			end
		end
		paintOne(seedX, seedY);
		while #blob < size do
			local candidates = {};
			local bi = 1;
			while bi <= #blob do
				local p = blob[bi];
				local dirs = neighborDirs(p[2]);
				local d = 1;
				while d <= 6 do
					local nx = p[1] + dirs[d][1];
					local ny = p[2] + dirs[d][2];
					if nx >= 0 and nx < iW and ny >= 0 and ny < iH and inBlob(blob, nx, ny) == false then
						table.insert(candidates, {nx, ny});
					end
					d = d + 1;
				end
				bi = bi + 1;
			end
			if #candidates < 1 then
				break
			end
			local pick = candidates[Map.Rand(#candidates, "DiagWater Island Grow") + 1];
			paintOne(pick[1], pick[2]);
			table.insert(blob, pick);
		end
		return blob;
	end
	local function carveMoat(blob)
		local bi = 1;
		while bi <= #blob do
			local p = blob[bi];
			local dirs = neighborDirs(p[2]);
			local d = 1;
			while d <= 6 do
				local nx = p[1] + dirs[d][1];
				local ny = p[2] + dirs[d][2];
				-- Off the west map edge is already water for this purpose --
				-- setPlot's own bounds check simply skips it, no gap needed.
				if nx >= 0 and nx < iW and ny >= 0 and ny < iH and inBlob(blob, nx, ny) == false then
					setPlot(nx, ny, PlotTypes.PLOT_OCEAN);
				end
				d = d + 1;
			end
			bi = bi + 1;
		end
	end

	local totalTiles = iW * iH;
	local pct = 6 + Map.Rand(5, "DiagWater TargetPct"); -- 6-10, centered ~8
	-- Every tile painted below also paints its mirror partner (setPlot does
	-- both), so the final salt water count ends up double whatever this
	-- function paints on the west side. Track everything in west-side units
	-- against half the full-map target, not the full target itself. Trimmed
	-- by 1% off the top since the coast covers less than the full height
	-- (see coastWinH below) and would otherwise just get pushed elsewhere
	-- instead of actually reduced.
	local westTarget = math.floor(totalTiles * (pct - 1) / 100 / 2);

	local mirrored = (DEF_MIRRORED == 1);
	local function inlandAllowed(x, y)
		if x < 4 then
			return false; -- stay clear of the back coast itself
		end
		if MirrorOwnsPlot(x, y, mirrored, iW) == false then
			return false
		end
		if WaterAllowedAtXY(x, y) == false then
			return false; -- respects the barrier's front-distance buffer
		end
		return true
	end

	local modeRoll = Map.Rand(100, "DiagWater Mode");
	local nInland = 0;
	if modeRoll >= 75 then
		nInland = 2;
	elseif modeRoll >= 50 then
		nInland = 1;
	end
	local usedByInland = 0;
	local ii = 1;
	while ii <= nInland do
		local size = 4 + Map.Rand(7, "DiagWater Inland Size"); -- 4-10
		local seedX, seedY;
		local attempt = 1;
		local xSpan = math.max(1, math.floor(iW * 0.4));
		while attempt <= 60 do
			local tx = 4 + Map.Rand(xSpan, "DiagWater Inland X");
			local ty = Map.Rand(iH, "DiagWater Inland Y");
			if inlandAllowed(tx, ty) then
				seedX, seedY = tx, ty;
				break
			end
			attempt = attempt + 1;
		end
		if seedX ~= nil then
			local blob = growWater(seedX, seedY, size, inlandAllowed);
			usedByInland = usedByInland + #blob;
		end
		ii = ii + 1;
	end

	local westBackBudget = westTarget - usedByInland;
	if westBackBudget < 6 then
		westBackBudget = 6;
	end

	-- Big island size and the bulge window's length are rolled up front so
	-- the bulge's reserved share of the budget can actually fit the island
	-- plus a moat, rather than being an arbitrary fixed depth.
	local bigSize = 5 + Map.Rand(11, "DiagWater Big Island Size"); -- 5-15
	local bulgeLen = 4 + Map.Rand(3, "DiagWater Bulge Len"); -- 4-6 rows

	-- The coast itself only covers some (60-80%, varies per map) of the
	-- map's height, not the full run -- picked as one contiguous, randomly-
	-- positioned window rather than spreading the gap out, so there's a real
	-- stretch of plain coastline at one or both ends instead of touching the
	-- back edge everywhere.
	local coastHeightPct = 60 + Map.Rand(21, "DiagWater Coast Height Pct"); -- 60-80
	local coastWinH = math.max(bulgeLen + 4, math.floor(iH * coastHeightPct / 100));
	if coastWinH > iH then
		coastWinH = iH;
	end
	local coastWinY0 = 0;
	if coastWinH < iH then
		coastWinY0 = Map.Rand(iH - coastWinH + 1, "DiagWater Coast Window");
	end
	local coastWinY1 = coastWinY0 + coastWinH; -- exclusive

	-- Continuous back coast: a random-walk-depth coastline (same idea as
	-- Standard's own back strip), but the bulge (for the big island) and the
	-- regular rows each draw a *share* of westBackBudget instead of the
	-- bulge being extra depth added on top of it -- that's what let the
	-- total run away before.
	local bulgeReserve = bigSize + 15; -- island + a generous moat/room allowance
	if bulgeReserve > westBackBudget * 0.7 then
		bulgeReserve = math.floor(westBackBudget * 0.7);
	end
	if bulgeReserve < bigSize then
		bulgeReserve = bigSize;
	end
	local regularBudget = westBackBudget - bulgeReserve;
	local regularRows = math.max(1, coastWinH - bulgeLen);
	local avgDepth = math.max(1, regularBudget / regularRows);
	local minD = 1;
	local maxD = math.max(minD + 1, math.ceil(avgDepth) + 1);
	local depth = math.max(1, math.floor(avgDepth + 0.5));
	local bulgeSpan = math.max(1, coastWinH - bulgeLen);
	local bulgeStart = coastWinY0 + Map.Rand(bulgeSpan, "DiagWater Bulge Start");
	local bulgeEnd = bulgeStart + bulgeLen - 1;
	local bulgeDepth = math.max(maxD + 2, math.floor(bulgeReserve / bulgeLen));

	local y = 0;
	while y < iH do
		if y < coastWinY0 or y >= coastWinY1 then
			-- Outside the coast window: mainland actually touches the true
			-- west edge here. GeneratePlotsByRegion unconditionally paints a
			-- 1-2 tile ocean rim along the whole west border before this
			-- function ever runs, so it has to be explicitly undone here or
			-- these rows would still show water regardless of the window.
			-- Only reclaim tiles that are actually still ocean (the rim) --
			-- setting the whole x=0..3 strip to flat land unconditionally was
			-- also erasing any hill/mountain the base tectonics fractal had
			-- already rolled at x=2/x=3 (outside the rim's real 1-2 tile
			-- width), leaving this strip noticeably flatter than the rest of
			-- the mainland.
			local x = 0;
			while x <= 3 do
				if getPlot(x, y) == PlotTypes.PLOT_OCEAN then
					setPlot(x, y, PlotTypes.PLOT_LAND);
				end
				x = x + 1;
			end
		else
			local step = Map.Rand(3, "DiagWater Coast Walk") - 1;
			depth = depth + step;
			if depth < minD then
				depth = minD;
			end
			if depth > maxD then
				depth = maxD;
			end
			local rowDepth = depth;
			if y >= bulgeStart and y <= bulgeEnd then
				rowDepth = bulgeDepth;
			end
			local x = 0;
			while x < rowDepth do
				setPlot(x, y, PlotTypes.PLOT_OCEAN);
				x = x + 1;
			end
		end
		y = y + 1;
	end

	-- Big island: forced, then moated, seeded inside the bulge so there's
	-- always room regardless of how the coast walk actually turned out.
	-- (bigSize was already rolled above, to size the bulge reservation.)
	local bigY = bulgeStart + Map.Rand(bulgeLen, "DiagWater Big Island Y");
	local bigX = 2 + Map.Rand(math.max(1, bulgeDepth - 3), "DiagWater Big Island X");
	local bigBlob = forceGrowLand(bigX, bigY, bigSize);
	carveMoat(bigBlob);

	-- Small islands sprayed through the thinner parts of the coast, outside
	-- the bulge.
	local nSmall = Map.Rand(7, "DiagWater Small Island Count"); -- 0-6
	local si = 1;
	while si <= nSmall do
		local ty = Map.Rand(iH, "DiagWater Small Island Y");
		if ty < bulgeStart - 1 or ty > bulgeEnd + 1 then
			local tx = Map.Rand(3, "DiagWater Small Island X");
			if getPlot(tx, ty) == PlotTypes.PLOT_OCEAN then
				local size = 1 + Map.Rand(4, "DiagWater Small Island Size"); -- 1-4
				local blob = forceGrowLand(tx, ty, size);
				carveMoat(blob);
			end
		end
		si = si + 1;
	end

	local diagLine = "DiagWater: pct=" .. pct .. " westTarget=" .. westTarget .. " inland=" .. nInland
		.. " usedByInland=" .. usedByInland .. " westBackBudget=" .. westBackBudget
		.. " bulgeReserve=" .. bulgeReserve .. " bigSize=" .. bigSize .. " smallCount=" .. nSmall
		.. " iH=" .. iH .. " coastHeightPct=" .. coastHeightPct
		.. " coastWinY0=" .. coastWinY0 .. " coastWinY1=" .. coastWinY1 .. " coastWinH=" .. coastWinH;
	print(diagLine);
	WeeveeDbg(diagLine);
end
------------------------------------------------------------------------------
function PlaceStandardEdgeSeas(plotTypes, iW, iH)
	if plotTypes == nil or IsStandardClimate() == false or IsTiltedMirrorAxis() then
		-- Standard-Diagonal's water (back coast, inland seas, islands) is
		-- entirely handled by PlaceDiagonalBackWater instead, from scratch.
		return
	end
	local cutIgnored, seas = ResolveSaltWaterPlan();
	if seas == nil or seas < 1 then
		return
	end
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local mid = math.floor(iW / 2) - 1;
	local function rowMid(y)
		if IsTiltedMirrorAxis() then
			return TiltedFoldMid(y) - 1;
		end
		return mid;
	end
	local function allowed(x, y)
		if x < 0 or y < 0 or y >= iH then
			return false
		end
		if MirrorOwnsPlot(x, y, true, iW) == false then
			return false
		end
		if WaterAllowedAtXY(x, y) == false then
			return false
		end
		return true
	end
	local function paint(x, y)
		plotTypes[y * iW + x + 1] = PlotTypes.PLOT_OCEAN;
		local mx = iW - x - 1;
		local my = iH - y - 1;
		plotTypes[my * iW + mx + 1] = PlotTypes.PLOT_OCEAN;
	end
	local n = 1;
	while n <= seas do
		local lakeSize = 3 + Map.Rand(8, "Standard Edge Sea Size");
		local edge = Map.Rand(3, "Standard sea edge");
		local seedX, seedY;
		local attempt = 1;
		while attempt <= 80 do
			local tx, ty;
			if edge == 0 then
				tx = Map.Rand(3, "Standard sea west x");
				ty = Map.Rand(iH, "Standard sea west y");
			elseif edge == 1 then
				ty = Map.Rand(2, "Standard sea south y");
				tx = Map.Rand(rowMid(ty) + 1, "Standard sea south x");
			else
				ty = iH - 1 - Map.Rand(2, "Standard sea north y");
				tx = Map.Rand(rowMid(ty) + 1, "Standard sea north x");
			end
			if allowed(tx, ty) then
				if edge == 0 or plotTypes[ty * iW + tx + 1] ~= PlotTypes.PLOT_OCEAN then
					seedX = tx;
					seedY = ty;
					break
				end
			end
			attempt = attempt + 1;
		end
		if seedX ~= nil then
			local blob = {{seedX, seedY}};
			paint(seedX, seedY);
			while #blob < lakeSize do
				local candidates = {};
				local bi = 1;
				while bi <= #blob do
					local p = blob[bi];
					local dirs = evenN;
					if p[2] % 2 == 1 then
						dirs = oddN;
					end
					local d = 1;
					while d <= 6 do
						local nx = p[1] + dirs[d][1];
						local ny = p[2] + dirs[d][2];
						if allowed(nx, ny) and plotTypes[ny * iW + nx + 1] ~= PlotTypes.PLOT_OCEAN then
							table.insert(candidates, {nx, ny});
						end
						d = d + 1;
					end
					bi = bi + 1;
				end
				if #candidates < 1 then
					break
				end
				local pick = candidates[Map.Rand(#candidates, "Standard Edge Sea Grow") + 1];
				paint(pick[1], pick[2]);
				table.insert(blob, pick);
			end
		end
		n = n + 1;
	end
	print("Standard edge seas:", seas);
end
-------------------------------------------------------------------------------
function FrostyInjectSnowForestResourceLists(self)
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if skip[x] ~= true and self.playerCollisionData[i] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetResourceType(-1) == -1
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
					local pt = plot:GetPlotType();
					local feat = plot:GetFeatureType();
					if pt == PlotTypes.PLOT_LAND and feat == FeatureTypes.FEATURE_FOREST then
						table.insert(self.tundra_flat_including_forests, i);
						table.insert(self.extra_deer_list, i);
					elseif pt == PlotTypes.PLOT_HILLS then
						table.insert(self.hills_list, i);
						if feat == FeatureTypes.FEATURE_FOREST then
							table.insert(self.extra_deer_list, i);
							table.insert(self.hills_forest_list, i);
							table.insert(self.hills_covered_list, i);
						elseif feat == FeatureTypes.NO_FEATURE then
							table.insert(self.marble_list, i);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local k = #self.forest_flat_that_are_not_tundra;
	while k >= 1 do
		local i = self.forest_flat_that_are_not_tundra[k];
		local px = (i - 1) % iW;
		local py = math.floor((i - 1) / iW);
		local plot = Map.GetPlot(px, py);
		if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
			table.remove(self.forest_flat_that_are_not_tundra, k);
		end
		k = k - 1;
	end
	self.extra_deer_list = GetShuffledCopyOfTable(self.extra_deer_list);
	self.hills_list = GetShuffledCopyOfTable(self.hills_list);
	self.marble_list = GetShuffledCopyOfTable(self.marble_list);
end
------------------------------------------------------------------------------
function FrostyAugmentLuxuryLists(lists, acceptXY)
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" or lists == nil then
		return lists
	end
	if lists[4] == nil or lists[5] == nil or lists[7] == nil or lists[14] == nil or lists[15] == nil then
		return lists
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and acceptXY(x, y) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
					local i = y * iW + x + 1;
					local pt = plot:GetPlotType();
					local feat = plot:GetFeatureType();
					if pt == PlotTypes.PLOT_LAND and feat == FeatureTypes.FEATURE_FOREST then
						table.insert(lists[14], i);
					elseif pt == PlotTypes.PLOT_HILLS then
						if feat == FeatureTypes.FEATURE_FOREST then
							table.insert(lists[7], i);
							table.insert(lists[5], i);
						elseif feat == FeatureTypes.NO_FEATURE then
							table.insert(lists[4], i);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local kept = {};
	local k = 1;
	while k <= #lists[15] do
		local i = lists[15][k];
		local px = (i - 1) % iW;
		local py = math.floor((i - 1) / iW);
		local plot = Map.GetPlot(px, py);
		if plot == nil or plot:GetTerrainType() ~= TerrainTypes.TERRAIN_SNOW then
			table.insert(kept, i);
		end
		k = k + 1;
	end
	lists[15] = kept;
	return lists
end
------------------------------------------------------------------------------
local ASP_GenerateLuxuryPlotListsAtCitySite = AssignStartingPlots.GenerateLuxuryPlotListsAtCitySite;
function AssignStartingPlots:GenerateLuxuryPlotListsAtCitySite(x, y, radius, bRemoveFeatureIce)
	local lists = ASP_GenerateLuxuryPlotListsAtCitySite(self, x, y, radius, bRemoveFeatureIce);
	lists = FilterTongueHomeLuxuryLists(lists);
	if bRemoveFeatureIce == true then
		return lists
	end
	return FrostyAugmentLuxuryLists(lists, function(px, py)
		return Map.PlotDistance(x, y, px, py) <= radius;
	end);
end
------------------------------------------------------------------------------
local ASP_GenerateLuxuryPlotListsInRegion = AssignStartingPlots.GenerateLuxuryPlotListsInRegion;
function AssignStartingPlots:GenerateLuxuryPlotListsInRegion(region_number)
	local lists = ASP_GenerateLuxuryPlotListsInRegion(self, region_number);
	lists = FilterTongueHomeLuxuryLists(lists);
	local region_data_table = self.regionData[region_number];
	if region_data_table == nil then
		return lists
	end
	local iW, iH = Map.GetGridSize();
	local iWestX = region_data_table[1];
	local iSouthY = region_data_table[2];
	local iWidth = region_data_table[3];
	local iHeight = region_data_table[4];
	return FrostyAugmentLuxuryLists(lists, function(px, py)
		local rx = (px - iWestX) % iW;
		local ry = (py - iSouthY) % iH;
		return rx < iWidth and ry < iHeight;
	end);
end
------------------------------------------------------------------------------
local ASP_GenerateGlobalResourcePlotLists = AssignStartingPlots.GenerateGlobalResourcePlotLists;
function AssignStartingPlots:GenerateGlobalResourcePlotLists()
	ASP_GenerateGlobalResourcePlotLists(self);
	FilterTongueHomeResourceLists(self);
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "wasteland" then
		local iW, iH = Map.GetGridSize();
		local skip = {};
		local cols = GetSnowWrapColumns(iW);
		local ci = 1;
		while ci <= #cols do
			skip[cols[ci]] = true;
			ci = ci + 1;
		end
		cols = GetSnowWrapTundraColumns(iW);
		ci = 1;
		while ci <= #cols do
			skip[cols[ci]] = true;
			ci = ci + 1;
		end
		local extraHills = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				local i = y * iW + x + 1;
				if skip[x] ~= true and self.playerCollisionData[i] ~= true then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil
						and plot:GetPlotType() == PlotTypes.PLOT_HILLS
						and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
						and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
						table.insert(extraHills, i);
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local hi = 1;
		while hi <= #extraHills do
			table.insert(self.extra_deer_list, extraHills[hi]);
			hi = hi + 1;
		end
		self.extra_deer_list = GetShuffledCopyOfTable(self.extra_deer_list);
	end
	if cfg ~= nil and cfg.kind == "frosty" then
		FrostyInjectSnowForestResourceLists(self);
	end
	if IsSnowBarrier() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local i = y * iW + x + 1;
			if self.playerCollisionData[i] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetPlotType() == PlotTypes.PLOT_OCEAN
					and plot:GetResourceType(-1) == -1
					and plot:GetFeatureType() ~= FeatureTypes.FEATURE_ICE
					and plot:GetFeatureType() ~= self.feature_atoll
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_COAST
					and plot:IsLake() then
					table.insert(self.coast_list, i);
					if plot:IsAdjacentToLand() and isMiddle(x) then
						table.insert(self.front_coast_list, i);
					end
				end
			end
		end
	end
	self.coast_list = GetShuffledCopyOfTable(self.coast_list);
	self.front_coast_list = GetShuffledCopyOfTable(self.front_coast_list);
	self.coast_next_to_land_list = GetShuffledCopyOfTable(self.coast_next_to_land_list);
end
------------------------------------------------------------------------------
local ASP_ExaminePlotForNaturalWondersEligibility = AssignStartingPlots.ExaminePlotForNaturalWondersEligibility;
function AssignStartingPlots:ExaminePlotForNaturalWondersEligibility(x, y)
	if ASP_ExaminePlotForNaturalWondersEligibility(self, x, y) == false then
		return false
	end
	if PlotRejectsNaturalWonder(x, y) then
		return false
	end
	if IsSnowBarrier() then
		local iW = Map.GetGridSize();
		local snowCols = GetSnowWrapColumns(iW, y);
		local tundraCols = GetSnowWrapTundraColumns(iW, y);
		local i = 1;
		while snowCols[i] ~= nil do
			if x == snowCols[i] then
				return false
			end
			i = i + 1;
		end
		i = 1;
		while tundraCols[i] ~= nil do
			if x == tundraCols[i] then
				return false
			end
			i = i + 1;
		end
	end
	return true
end
------------------------------------------------------------------------------
function GetMajorStartPlots()
	local starts = {};
	local nMaj = 22;
	if GameDefines ~= nil and GameDefines.MAX_MAJOR_CIVS ~= nil then
		nMaj = GameDefines.MAX_MAJOR_CIVS;
	end
	local i = 0;
	while i < nMaj do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			table.insert(starts, player:GetStartingPlot());
		end
		i = i + 1;
	end
	return starts;
end
------------------------------------------------------------------------------
function WonderTooCloseToCapital(x, y)
	local starts = GetMajorStartPlots();
	local i = 1;
	while i <= #starts do
		-- Matches the vanilla natural-wonders ripple target (PlaceImpactAndRipples:
		-- "set a minimum distance of 5 plots (4 ripples) away").
		if Map.PlotDistance(x, y, starts[i]:GetX(), starts[i]:GetY()) <= 5 then
			return true
		end
		i = i + 1;
	end
	return false
end
------------------------------------------------------------------------------
local ASP_ExamineCandidatePlotForNaturalWondersEligibility = AssignStartingPlots.ExamineCandidatePlotForNaturalWondersEligibility;
function AssignStartingPlots:ExamineCandidatePlotForNaturalWondersEligibility(x, y)
	if WonderTooCloseToCapital(x, y) then
		return false
	end
	if PlotRejectsNaturalWonder(x, y) then
		return false
	end
	return ASP_ExamineCandidatePlotForNaturalWondersEligibility(self, x, y);
end
------------------------------------------------------------------------------
local ASP_AttemptToPlaceNaturalWonder = AssignStartingPlots.AttemptToPlaceNaturalWonder;
function AssignStartingPlots:AttemptToPlaceNaturalWonder(wonder_number, row_number)
	local orig = self.eligibility_lists[wonder_number];
	if orig == nil then
		return false
	end
	local iW = Map.GetGridSize();
	local kept = {};
	local i = 1;
	while orig[i] ~= nil do
		local plotIndex = orig[i];
		local x = (plotIndex - 1) % iW;
		local y = (plotIndex - x - 1) / iW;
		if WonderTooCloseToCapital(x, y) == false and PlotRejectsNaturalWonder(x, y) == false then
			table.insert(kept, plotIndex);
		end
		i = i + 1;
	end
	self.eligibility_lists[wonder_number] = kept;
	local ok = false;
	local sriBefore = nil;
	if #kept > 0 then
		if TypeIsSriPada(self.wonder_list[wonder_number]) then
			sriBefore = CollectSriPadaKeys();
			local buckets = {};
			local s = 0;
			while s <= 6 do
				buckets[s + 1] = {};
				s = s + 1;
			end
			local ki = 1;
			while kept[ki] ~= nil do
				local plotIndex = kept[ki];
				local px = (plotIndex - 1) % iW;
				local py = (plotIndex - px - 1) / iW;
				local score = SriPadaAdjPreferScore(px, py);
				if score < 0 then
					score = 0;
				end
				if score > 6 then
					score = 6;
				end
				table.insert(buckets[score + 1], plotIndex);
				ki = ki + 1;
			end
			s = 6;
			while s >= 0 and ok == false do
				local group = buckets[s + 1];
				if group ~= nil and #group > 0 then
					self.eligibility_lists[wonder_number] = group;
					ok = ASP_AttemptToPlaceNaturalWonder(self, wonder_number, row_number);
				end
				s = s - 1;
			end
		else
			ok = ASP_AttemptToPlaceNaturalWonder(self, wonder_number, row_number);
		end
	end
	self.eligibility_lists[wonder_number] = orig;
	if ok then
		FixKailashGibraltarAdjacency(self.wonder_list[wonder_number]);
		if sriBefore ~= nil then
			ShapeNewSriPada(sriBefore);
		end
	end
	return ok;
end
------------------------------------------------------------------------------
function FixKailashGibraltarAdjacency(wtype)
	if wtype == nil then
		return
	end
	local kailash = (wtype == "FEATURE_MT_KAILASH");
	local gibraltar = (wtype == "FEATURE_GIBRALTER" or wtype == "FEATURE_GIBRALTAR");
	if kailash == false and gibraltar == false then
		return
	end
	local featID = GameInfoTypes[wtype];
	if featID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:GetFeatureType() == featID then
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(x, y, d);
					if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						if kailash then
							adj:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						else
							adj:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
							adj:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
							adj:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
						end
						n = n + 1;
					end
					d = d + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("NW adjacency flattened:", wtype, n);
end
------------------------------------------------------------------------------
function StripSeparatorNaturalWonders()
	if IsTiltedMirrorAxis() == false then
		return
	end
	local nwFeat = {};
	for row in GameInfo.Features() do
		if row.NaturalWonder then
			nwFeat[row.ID] = true;
		end
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if PlotRejectsNaturalWonder(x, y) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local f = plot:GetFeatureType();
					if nwFeat[f] == true then
						plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Separator natural wonders stripped:", n);
end
------------------------------------------------------------------------------
function FeatureIsMtFuji(feat)
	if feat == nil or feat == FeatureTypes.NO_FEATURE then
		return false
	end
	local fujiID = GameInfoTypes["FEATURE_FUJI"];
	if fujiID ~= nil and feat == fujiID then
		return true
	end
	fujiID = GameInfoTypes["FEATURE_MT_FUJI"];
	if fujiID ~= nil and feat == fujiID then
		return true
	end
	local info = GameInfo.Features[feat];
	if info ~= nil and info.Type ~= nil then
		local t = string.upper(tostring(info.Type));
		if string.find(t, "FUJI", 1, true) ~= nil then
			return true
		end
	end
	return false
end
------------------------------------------------------------------------------
function MaybePlaceFujiHorses(asp)
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	if horseID == nil then
		return
	end
	local horseAmt = 4;
	if asp ~= nil and asp.GetMajorStrategicResourceQuantityValues ~= nil then
		local uIgnored, h = asp:GetMajorStrategicResourceQuantityValues();
		if h ~= nil and h > 0 then
			horseAmt = h;
		end
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and FeatureIsMtFuji(plot:GetFeatureType()) then
				if Map.Rand(100, "Fuji horses") < 2 then
					plot:SetResourceType(horseID, horseAmt);
					n = n + 1;
					if asp ~= nil and asp.amounts_of_resources_placed ~= nil then
						local slot = asp.amounts_of_resources_placed[horseID + 1];
						if slot == nil then
							slot = 0;
						end
						asp.amounts_of_resources_placed[horseID + 1] = slot + horseAmt;
					end
					print("Mt Fuji horse major at", x, y, "amt", horseAmt);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if n > 0 then
		print("Fuji horse nodes:", n);
	end
end
------------------------------------------------------------------------------
function TypeIsSriPada(wtype)
	if wtype == nil then
		return false
	end
	local t = string.upper(tostring(wtype));
	if string.find(t, "SRI", 1, true) ~= nil and string.find(t, "PADA", 1, true) ~= nil then
		return true
	end
	return false
end
------------------------------------------------------------------------------
function FeatureIsSriPada(feat)
	if feat == nil or feat == FeatureTypes.NO_FEATURE then
		return false
	end
	local info = GameInfo.Features[feat];
	if info ~= nil and info.Type ~= nil then
		return TypeIsSriPada(info.Type);
	end
	return false
end
------------------------------------------------------------------------------
function SriPadaAdjPreferScore(x, y)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil then
			if adj:IsWater() or adj:GetPlotType() == PlotTypes.PLOT_LAND then
				n = n + 1;
			end
		end
		d = d + 1;
	end
	return n
end
------------------------------------------------------------------------------
function PlotHasNaturalWonder(plot)
	if plot == nil then
		return true
	end
	local f = plot:GetFeatureType();
	if f == nil or f == FeatureTypes.NO_FEATURE then
		return false
	end
	local info = GameInfo.Features[f];
	if info ~= nil and info.NaturalWonder then
		return true
	end
	return false
end
------------------------------------------------------------------------------
function PlotIsMajorStart(plot)
	if plot == nil then
		return false
	end
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil and sp:GetX() == plot:GetX() and sp:GetY() == plot:GetY() then
				return true
			end
		end
		pi = pi + 1;
	end
	return false
end
------------------------------------------------------------------------------
function WeeveeMajorStartIndexSet()
	local keys = {};
	local iW = Map.GetGridSize();
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil then
				keys[sp:GetY() * iW + sp:GetX() + 1] = true;
			end
		end
		pi = pi + 1;
	end
	return keys
end
------------------------------------------------------------------------------
function PlotCanBecomeHills(plot)
	if plot == nil or plot:IsWater() then
		return false
	end
	if plot:GetPlotType() ~= PlotTypes.PLOT_LAND then
		return false
	end
	if PlotHasNaturalWonder(plot) then
		return false
	end
	local feat = plot:GetFeatureType();
	if feat == FeatureTypes.FEATURE_OASIS
		or feat == FeatureTypes.FEATURE_FLOOD_PLAINS
		or feat == FeatureTypes.FEATURE_MARSH
		or feat == FeatureTypes.FEATURE_ICE then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function TryConvertPlotToHills(plot)
	if PlotCanBecomeHills(plot) == false then
		return false
	end
	local res = plot:GetResourceType(-1);
	plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
	if res ~= nil and res ~= -1 and plot:CanHaveResource(res) == false then
		plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		return false
	end
	return true
end
------------------------------------------------------------------------------
function CollectSriPadaKeys()
	local keys = {};
	local iW, iH = Map.GetGridSize();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and FeatureIsSriPada(plot:GetFeatureType()) then
				keys[y * iW + x + 1] = true;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	return keys
end
------------------------------------------------------------------------------
function ShapeSriPadaAt(x, y)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_HILLS and PlotHasNaturalWonder(adj) == false then
			local toWater = false;
			if PlotIsMajorStart(adj) == false and Map.Rand(2, "Sri Pada adj water") == 0 then
				toWater = true;
			end
			if toWater then
				adj:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				adj:SetResourceType(-1);
				adj:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
				adj:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
			else
				adj:SetPlotType(PlotTypes.PLOT_LAND, false, false);
			end
		end
		d = d + 1;
	end
	local cands = {};
	local dy = y - 2;
	while dy <= y + 2 do
		local dx = x - 2;
		while dx <= x + 2 do
			if Map.PlotDistance(x, y, dx, dy) >= 1 and Map.PlotDistance(x, y, dx, dy) <= 2 then
				local p = Map.GetPlot(dx, dy);
				if PlotCanBecomeHills(p) then
					table.insert(cands, p);
				end
			end
			dx = dx + 1;
		end
		dy = dy + 1;
	end
	if #cands > 1 then
		cands = GetShuffledCopyOfTable(cands);
	end
	local n = 0;
	local i = 1;
	while i <= #cands and n < 3 do
		if TryConvertPlotToHills(cands[i]) then
			n = n + 1;
		end
		i = i + 1;
	end
	print("Sri Pada shaped at", x, y, "r2 hills", n);
end
------------------------------------------------------------------------------
function ShapeNewSriPada(beforeKeys)
	local iW, iH = Map.GetGridSize();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local key = y * iW + x + 1;
			if beforeKeys == nil or beforeKeys[key] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and FeatureIsSriPada(plot:GetFeatureType()) then
					ShapeSriPadaAt(x, y);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function EnsureStartHillsFloor()
	local iW, iH = Map.GetGridSize();
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local sp = player:GetStartingPlot();
			local sx = sp:GetX();
			local sy = sp:GetY();
			if not (DEF_MIRRORED == 1 and sx >= iW / 2) then
				local nHills = 0;
				local flats = {};
				local dy = sy - 3;
				while dy <= sy + 3 do
					local dx = sx - 3;
					while dx <= sx + 3 do
						if Map.PlotDistance(sx, sy, dx, dy) <= 3 then
							local p = Map.GetPlot(dx, dy);
							if p ~= nil then
								if p:GetPlotType() == PlotTypes.PLOT_HILLS then
									nHills = nHills + 1;
								elseif PlotCanBecomeHills(p) then
									table.insert(flats, p);
								end
							end
						end
						dx = dx + 1;
					end
					dy = dy + 1;
				end
				if nHills < 5 and #flats > 0 then
					if #flats > 1 then
						flats = GetShuffledCopyOfTable(flats);
					end
					local i = 1;
					while i <= #flats and nHills < 5 do
						if TryConvertPlotToHills(flats[i]) then
							nHills = nHills + 1;
						end
						i = i + 1;
					end
					print("Start hills floor", sx, sy, "now", nHills);
				end
			end
		end
		pi = pi + 1;
	end
end
-------------------------------------------------------------------------------
-- The back-coast columns (x=0..3) get their water shaped after the tectonics
-- pass, and every shaper (ShapeNoWrapBackstrip, PlaceDiagonalBackWater, ...)
-- writes flat PLOT_LAND wherever it reclaims or resets land there, so those
-- columns lost the hills the hills fractal would have given them. Instead of
-- patching each shaper, GeneratePlotsByRegion runs the tectonics pass with
-- the ocean rim temporarily turned back into land, keeps the result for
-- x=0..3 in `tectonic`, and calls this at the very end: any tile in those
-- columns that ended up flat land but that the tectonics pass called hills
-- becomes hills, so surviving back-coast land follows the same hill profile
-- as the land in the middle. Mountains are deliberately not restored.
-- Works on the west columns and applies the same change to the 180-degree
-- mirror tile, matching how the shapers mirror x=0..3.
function RestoreBackTectonicHills(plotTypes, tectonic, iW, iH)
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= 3 do
			local i = y * iW + x + 1;
			if plotTypes[i] == PlotTypes.PLOT_LAND and tectonic[i] == PlotTypes.PLOT_HILLS then
				plotTypes[i] = PlotTypes.PLOT_HILLS;
				local mi = (iH - y - 1) * iW + (iW - x - 1) + 1;
				if plotTypes[mi] == PlotTypes.PLOT_LAND then
					plotTypes[mi] = PlotTypes.PLOT_HILLS;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function PurgeNearStartLakeFish()
	if IsSnowBarrier() == false then
		return
	end
	local fishID = GameInfoTypes["RESOURCE_FISH"];
	if fishID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local starts = {};
	for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		local player = Players[i];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			table.insert(starts, player:GetStartingPlot());
		end
	end
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local plot = Map.GetPlot(x, y);
			if plot:GetResourceType(-1) == fishID and plot:IsWater() then
				local area = plot:Area();
				if area ~= nil and area:GetNumTiles() <= 6 then
					for _, startPlot in ipairs(starts) do
						if Map.PlotDistance(x, y, startPlot:GetX(), startPlot:GetY()) <= 4 then
							plot:SetResourceType(-1);
							break
						end
					end
				end
			end
		end
	end
end
------------------------------------------------------------------------------
function IsCappedSeaResource(res)
	if res == nil or res == -1 then
		return false
	end
	if res == GameInfoTypes["RESOURCE_FISH"] then
		return true
	end
	if res == GameInfoTypes["RESOURCE_PEARLS"] then
		return true
	end
	if res == GameInfoTypes["RESOURCE_WHALE"] then
		return true
	end
	if res == GameInfoTypes["RESOURCE_CORAL"] then
		return true
	end
	if res == GameInfoTypes["RESOURCE_CRAB"] then
		return true
	end
	return false
end
------------------------------------------------------------------------------
function GetSaltCoastPlotIndices(asp)
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW * 0.5);
	end
	local list = {};
	local y = 0;
	while y < iH do
		local skip = {};
		local cols = GetSnowWrapColumns(iW, y);
		local ci = 1;
		while ci <= #cols do
			skip[cols[ci]] = true;
			ci = ci + 1;
		end
		cols = GetSnowWrapTundraColumns(iW, y);
		ci = 1;
		while ci <= #cols do
			skip[cols[ci]] = true;
			ci = ci + 1;
		end
		local x = 0;
		while x <= maxX do
			if skip[x] ~= true and (IsTiltedMirrorAxis() == false or TongueResourcePlotOk(x, y)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetPlotType() == PlotTypes.PLOT_OCEAN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_COAST
					and plot:IsLake() == false
					and plot:IsAdjacentToLand()
					and plot:GetResourceType(-1) == -1 then
					local feat = plot:GetFeatureType();
					if feat ~= FeatureTypes.FEATURE_ICE and (asp == nil or asp.feature_atoll == nil or feat ~= asp.feature_atoll) then
						table.insert(list, y * iW + x + 1);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	return list;
end
------------------------------------------------------------------------------
function GetWastelandSaltCoastPlotIndices(asp)
	return GetSaltCoastPlotIndices(asp);
end
------------------------------------------------------------------------------
function CountWastelandResource(resID)
	local n = 0;
	if resID == nil then
		return 0
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW * 0.5);
	end
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:GetResourceType(-1) == resID then
				n = n + 1;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	return n
end
------------------------------------------------------------------------------
function RescueUnplacedLuxuryTypes(asp)
	if asp == nil then
		return
	end
	local coastal = WastelandCoastalLuxuryIDs(asp);
	local seen = {};
	local nRescued = 0;
	local maxRescue = 2;
	local function isCoastalLux(id)
		local c = 1;
		while coastal[c] ~= nil do
			if coastal[c] == id then
				return true
			end
			c = c + 1;
		end
		return false
	end
	local function consider(id)
		if id == nil or seen[id] == true or nRescued >= maxRescue then
			return
		end
		seen[id] = true;
		if isCoastalLux(id) then
			return
		end
		local n = asp.amounts_of_resources_placed[id + 1];
		if n ~= nil and n > 0 then
			return
		end
		local p, s, t, q = asp:GetIndicesForLuxuryType(id);
		local idx = {p, s, t, q};
		local left = 1;
		local li = 1;
		while li <= 4 and left > 0 do
			local listIdx = idx[li];
			if listIdx ~= nil and listIdx > 0 and asp.global_luxury_plot_lists[listIdx] ~= nil then
				local shuf = GetShuffledCopyOfTable(asp.global_luxury_plot_lists[listIdx]);
				left = asp:PlaceSpecificNumberOfResources(id, 1, left, 1, -1, 0, 0, shuf);
			end
			li = li + 1;
		end
		if left < 1 then
			nRescued = nRescued + 1;
		end
		print("Rescue unplaced lux", id, "left", left);
	end
	local bags = {
		asp.resourceIDs_assigned_to_regions,
		asp.resourceIDs_assigned_to_cs,
		asp.resourceIDs_assigned_to_random,
		asp.resourceIDs_assigned_to_special_case
	};
	local b = 1;
	while bags[b] ~= nil do
		local bag = bags[b];
		local i = 1;
		while bag[i] ~= nil do
			consider(bag[i]);
			i = i + 1;
		end
		b = b + 1;
	end
end
------------------------------------------------------------------------------
function ForceCoastalLuxuries(asp)
	if asp == nil then
		return
	end
	local picked = asp.forcedCoastalLux;
	if picked == nil then
		picked = asp.wastelandForcedCoastalLux;
	end
	if picked == nil or #picked < 1 then
		ForceCoastalLuxuryRoles(asp);
		picked = asp.forcedCoastalLux;
	end
	if picked == nil or #picked < 1 then
		return
	end
	local plots = GetShuffledCopyOfTable(GetSaltCoastPlotIndices(asp));
	local i = 1;
	while i <= #picked do
		local id = picked[i];
		local have = CountWastelandResource(id);
		local want = 1;
		if have < want then
			local left = asp:PlaceSpecificNumberOfResources(id, 1, want - have, 1, -1, 0, 0, plots);
			print("Coastal lux force id", id, "had", have, "left", left);
		end
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function ForceWastelandCoastalLuxuries(asp)
	ForceCoastalLuxuries(asp);
end
------------------------------------------------------------------------------
local PlaceFishVanilla = AssignStartingPlots.PlaceFish;
function AssignStartingPlots:PlaceFish(frequency, plot_list)
	if plot_list == self.front_coast_list then
		return
	end
	if frequency ~= nil then
		frequency = frequency * 1.25;
	end
	PlaceFishVanilla(self, frequency, plot_list);
end
------------------------------------------------------------------------------
function CapSeaResources()
	local cap = 15;
	local iW, iH = Map.GetGridSize();
	local maxX = iW;
	if DEF_MIRRORED == 1 then
		maxX = iW * 0.5;
	end
	local fishID = GameInfoTypes["RESOURCE_FISH"];
	local fishPlots = {};
	local otherPlots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:IsWater() then
				local res = plot:GetResourceType(-1);
				if IsCappedSeaResource(res) then
					if res == fishID then
						table.insert(fishPlots, plot);
					else
						table.insert(otherPlots, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nFish = #fishPlots;
	local nOther = #otherPlots;
	local n = nFish + nOther;
	if n <= cap then
		print("Sea resources (pre-mirror):", n, "fish=", nFish, "coastLux=", nOther);
		return
	end
	local excess = n - cap;
	local removedFish = 0;
	local fishShuffled = GetShuffledCopyOfTable(fishPlots);
	local i = 1;
	while i <= nFish and removedFish < excess do
		fishShuffled[i]:SetResourceType(-1);
		removedFish = removedFish + 1;
		i = i + 1;
	end
	local stillNeed = excess - removedFish;
	local removedLux = 0;
	if stillNeed > 0 and IsStandardClimate() == false then
		local otherShuffled = GetShuffledCopyOfTable(otherPlots);
		local j = 1;
		while j <= stillNeed and j <= #otherShuffled do
			otherShuffled[j]:SetResourceType(-1);
			removedLux = removedLux + 1;
			j = j + 1;
		end
	end
	print("Sea resources (pre-mirror) capped:", n, "->", n - removedFish - removedLux, "removed fish=", removedFish, "removed lux=", removedLux);
end
------------------------------------------------------------------------------
function ThinOasisCoastalLuxuries()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW * 0.5);
	end
	local seen = {};
	local stripped = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local i = y * iW + x + 1;
			if seen[i] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() then
					local body = {};
					local q = {plot};
					local qi = 1;
					seen[i] = true;
					table.insert(body, plot);
					while qi <= #q do
						local p = q[qi];
						qi = qi + 1;
						local d = 0;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
							if adj ~= nil and adj:IsWater() then
								local ax = adj:GetX();
								if ax <= maxX then
									local ai = adj:GetY() * iW + ax + 1;
									if seen[ai] ~= true then
										seen[ai] = true;
										table.insert(q, adj);
										table.insert(body, adj);
									end
								end
							end
							d = d + 1;
						end
					end
					local byType = {};
					local bi = 1;
					while bi <= #body do
						local res = body[bi]:GetResourceType(-1);
						if IsCappedSeaResource(res) and res ~= GameInfoTypes["RESOURCE_FISH"] then
							if byType[res] == nil then
								byType[res] = {};
							end
							table.insert(byType[res], body[bi]);
						end
						bi = bi + 1;
					end
					local keep = 1;
					if #body > 8 then
						keep = 2;
					end
					local res, tiles;
					for res, tiles in pairs(byType) do
						if #tiles > keep then
							tiles = GetShuffledCopyOfTable(tiles);
							local ti = keep + 1;
							while ti <= #tiles do
								tiles[ti]:SetResourceType(-1);
								stripped = stripped + 1;
								ti = ti + 1;
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis coastal lux thinned:", stripped);
end
-------------------------------------------------------------------------------
function MultilayeredFractal:GeneratePlotsByRegion()
	-- Sirian's MultilayeredFractal controlling function.
	-- You -MUST- customize this function for each script using MultilayeredFractal.
	--
	-- This implementation is specific to West vs East.
	local iW, iH = Map.GetGridSize();
	local fracFlags = {};
	local SplitOps = Map.GetCustomOption(OPT_CENTER_SPLIT);

	-- Fill all rows with land plots.
	self.wholeworldPlotTypes = table.fill(PlotTypes.PLOT_LAND, iW * iH);

	if false then -- Ocean Strip
	
		-- Add strip of ocean to middle of map --- Always start with this for civ placements
		for y = 0, iH - 1 do
			for x = math.floor(iW / 2) - 2, math.floor(iW / 2) + 1 do
				local plotIndex = y * iW + x + 1;
				--if y >= math.floor(iH / 2) - 2 and y <= math.floor(iH / 2) + 1 then
					--if x == math.floor(iW / 2) or x == math.floor(iW / 2) - 1 then
						--self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
					--end
				--else
					self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
				--end
			end
		end
	elseif false then -- Landbridges
		
		-- Add strip of ocean to middle of map --- Always start with this for civ placements
		for y = 4, iH - 5 do
			for x = math.floor(iW / 2) - 2, math.floor(iW / 2) + 1 do
				local plotIndex = y * iW + x + 1;
				if y >= math.floor(iH / 2) - 2 and y <= math.floor(iH / 2) + 1 then
					if x == math.floor(iW / 2) or x == math.floor(iW / 2) - 1 then
						--self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
					end
				else
					self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
				end
			end
		end
	end
	if false then -- Barrier Islands
		
		-- Add strip of ocean to middle of map --- Always start with this for civ placements
		for y = 0, iH - 1 do
			for x = math.floor(iW / 2) - 2, math.floor(iW / 2) + 1 do
				local plotIndex = y * iW + x + 1;
					self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
			end
		end
		local x_middle = math.floor(iW / 2) - 5;
		for y = 0, iH do
			local plotIndex = y * iW + x_middle + 1;
			self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
		end
		local outer_half = {};
		for loop = 1, iH - 2 do
			table.insert(outer_half, loop);
		end
		local outer_shuffled = GetShuffledCopyOfTable(outer_half)
		local iNumOuterPerColumn = math.floor(iH * 0.67);
		local x_outer = math.floor((iW / 2) - 4);
		for loop = 1, iNumOuterPerColumn do
			local y_outer = outer_shuffled[loop];
			local i_outer_plot = y_outer * iW + x_outer + 1;
			self.wholeworldPlotTypes[i_outer_plot] = PlotTypes.PLOT_OCEAN;
		end
		local x_outerst = math.floor((iW / 2) - 3);
		local iNumOuterstPerColumn = math.floor(iH * 0.33);
		for loop = 1, iNumOuterstPerColumn do
			local y_outerst = outer_shuffled[loop];
			local i_outerst_plot = y_outerst * iW + x_outerst + 1;
			self.wholeworldPlotTypes[i_outerst_plot] = PlotTypes.PLOT_OCEAN;
		end
		local inner_half = {};
		for loop = 1, iH - 2 do
			table.insert(inner_half, loop);
		end
		local inner_shuffled = GetShuffledCopyOfTable(inner_half)
		local iNumInnerPerColumn = math.max(math.floor(iH * 0.33), math.floor((iH / 3) - 1));
		local x_inner = math.floor((iW / 2) - 6);	
		for loop = 1, iNumInnerPerColumn do
			local y_inner = inner_shuffled[loop];
			local i_inner_plot = y_inner * iW + x_inner + 1;
			self.wholeworldPlotTypes[i_inner_plot] = PlotTypes.PLOT_OCEAN;
		end
		local x_innerst = math.floor((iW / 2) - 7);
		local iNumInnerstPerColumn = math.floor(iH * 0.17);
		for loop = 1, iNumInnerstPerColumn do
			local y_innerst = inner_shuffled[loop];
			local i_innerst_plot = y_innerst * iW + x_innerst + 1;
			self.wholeworldPlotTypes[i_innerst_plot] = PlotTypes.PLOT_OCEAN;
		end
	end
	if not IsSnowWrapX() and IsOasisClimate() == false then
		for x = 0, 0 do
			for y = 1, iH - 2 do
				local i = y * iW + x + 1;
				self.wholeworldPlotTypes[i] = PlotTypes.PLOT_HILLS;
			end
		end
		

		for x = 0, 0 do
			local i = x + 1;
			self.wholeworldPlotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
			local i = (iH - 1) * iW + x + 1;
			self.wholeworldPlotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
		end
		local west_half = {};
		for loop = 1, iH - 2 do
			table.insert(west_half, loop);
		end
		local west_shuffled = GetShuffledCopyOfTable(west_half)
		local iNumMountainsPerColumn = math.max(math.floor(iH * 0.33), math.floor((iH / 3) - 1));
		local x_west = 3;
		if IsSnowNoWrap() then
			x_west = 2;
		end
		for loop = 1, iNumMountainsPerColumn do
			local y_west = west_shuffled[loop];
			local i_west_plot = y_west * iW + x_west + 1;
			self.wholeworldPlotTypes[i_west_plot] = PlotTypes.PLOT_OCEAN;
		end
		-- Add strips of ocean to the world borders.
		local rimW = 2;
		if IsSnowNoWrap() then
			rimW = 1;
		end
		for y = 0, iH do
			for x = 0, rimW do
				local plotIndex = y * iW + x + 1;
				self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
			end
		end
		for y = 0, iH do
			for x = iW - 1 - rimW, iW do
				local plotIndex = y * iW + x + 1;
				self.wholeworldPlotTypes[plotIndex] = PlotTypes.PLOT_OCEAN;
			end
		end
	end

	-- Add lakes.
	local lakesFrac = Fractal.Create(iW, iH, lake_grain, fracFlags, 6, 6);
	local iLakesThreshold = lakesFrac:GetHeight(92);
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local i = y * iW + x + 1; -- add one because Lua arrays start at 1
			local lakeVal = lakesFrac:GetHeight(x, y);
			if lakeVal >= iLakesThreshold then
				--self.wholeworldPlotTypes[i] = PlotTypes.PLOT_OCEAN;
			end
		end
	end


	-- Land and water are set. Now apply hills and mountains.
	local world_age = DEF_WORLD_AGE;
	if world_age == 4 then
		world_age = 1 + Map.Rand(3, "Random World Age - Lua");
	end
	local args = {world_age = world_age};
	-- self.iTerrainFlags mirrors the real map's WrapX (false by default here
	-- -- see GetMapInitData/IsSnowWrapX), so ApplyTectonics' own hillsFrac/
	-- mountainsFrac fractals are built non-wrapped in X. Civ5's native
	-- Fractal class tapers toward flat, low-variance height values near a
	-- non-wrapped edge (it has no "other side" neighbor data to draw
	-- randomness from), which was silently starving hills/mountains in the
	-- leftmost ~2-3 columns (and, by the mirror, the rightmost ~2-3) --
	-- confirmed via WeeveeLogFlatHillSample: column 0 came back ~0-9% hills
	-- vs ~30-45% by column 3+, in both Standard and Murky. Force wrap-X on
	-- just for this call -- it only smooths the noise driving hill/mountain
	-- placement, it doesn't make the actual map wrap -- then restore it,
	-- since iTerrainFlags is also read by the land/water layers.
	local savedWrapX = self.iTerrainFlags.FRAC_WRAP_X;
	self.iTerrainFlags.FRAC_WRAP_X = true;
	-- ApplyTectonics skips ocean, so the ocean rim painted above would get no
	-- hills at all. Turn the west rim back into land just for this call, keep
	-- what the tectonics pass made of x=0..3 (see RestoreBackTectonicHills),
	-- then put the rim back so the rest of the pipeline sees what it always did.
	local backTectonic = nil;
	local backRimMask = {};
	if (not IsSnowWrapX()) and IsOasisClimate() == false then
		backTectonic = {};
		for y = 0, iH - 1 do
			for x = 0, 3 do
				local i = y * iW + x + 1;
				if self.wholeworldPlotTypes[i] == PlotTypes.PLOT_OCEAN then
					backRimMask[i] = true;
					self.wholeworldPlotTypes[i] = PlotTypes.PLOT_LAND;
				end
			end
		end
	end
	self:ApplyTectonics(args)
	if backTectonic ~= nil then
		for y = 0, iH - 1 do
			for x = 0, 3 do
				local i = y * iW + x + 1;
				backTectonic[i] = self.wholeworldPlotTypes[i];
				if backRimMask[i] then
					self.wholeworldPlotTypes[i] = PlotTypes.PLOT_OCEAN;
				end
			end
		end
	end
	self.iTerrainFlags.FRAC_WRAP_X = savedWrapX;

	if false then -- Skirmish
		for x = iW / 2 - 2, iW / 2 + 1 do
			for y = 1, iH - 2 do
				local i = y * iW + x + 1;
				self.wholeworldPlotTypes[i] = PlotTypes.PLOT_LAND;
			end
		end
		for x = iW / 2 - 2, iW / 2 + 1 do
			local i = x + 1;
			self.wholeworldPlotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
			local i = (iH - 1) * iW + x + 1;
			self.wholeworldPlotTypes[i] = PlotTypes.PLOT_MOUNTAIN;
		end
		local west_half, east_half = {}, {};
		for loop = 1, iH - 2 do
			table.insert(west_half, loop);
			table.insert(east_half, loop);
		end
		local west_shuffled = GetShuffledCopyOfTable(west_half)
		local east_shuffled = GetShuffledCopyOfTable(east_half)
		local iNumMountainsPerColumn = math.max(math.floor(iH * 0.225), math.floor((iH / 4) - 1));
		local x_west, x_east = iW / 2 - 1, iW / 2;
		for loop = 1, iNumMountainsPerColumn do
			local y_west, y_east = west_shuffled[loop], iH - 1- west_shuffled[loop];
			local i_west_plot = y_west * iW + x_west + 1;
			local i_east_plot = y_east * iW + x_east + 1;
			self.wholeworldPlotTypes[i_west_plot] = PlotTypes.PLOT_MOUNTAIN;
			self.wholeworldPlotTypes[i_east_plot] = PlotTypes.PLOT_MOUNTAIN;
		end
	end
	frontMountainZones = {};
	if IsSnowBarrier() then
		local cfg = GetBarrierConfig();
		local mountainDensity = FRONT_MOUNTAIN_DENSITY;
		if cfg.kind == "peaks" then
			local col1, col2, col3, col4, col5 = GetFrontMountainColumns5West(iW);
			PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, col1, col2, col3);
			if not DISABLE_FRONT_MOUNTAIN_RIDGES then
				PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, col1, col2, col3, col4, col5, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
			end
			if IsSnowWrapX() then
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1);
				if not DISABLE_FRONT_MOUNTAIN_RIDGES then
					PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 2, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1, x_wrap_west + 2, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
				end
			end
		elseif cfg.kind == "snow" and cfg.tilted ~= true then
			local col1, col2, col3, col4, col5 = GetFrontMountainColumns5West(iW);
			PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, col1, col2, col3);
			if not DISABLE_FRONT_MOUNTAIN_RIDGES then
				PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, col1, col2, col3, col4, col5, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
			end
			if IsSnowWrapX() then
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1);
				if not DISABLE_FRONT_MOUNTAIN_RIDGES then
					PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 2, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1, x_wrap_west + 2, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
				end
			end
		elseif cfg.kind == "snow" and cfg.tilted == true then
			-- Standard-Diagonal: same field design, but the five columns are
			-- offsets from the row-local fold instead of fixed columns, so
			-- the field tracks the diagonal barrier.
			local off1, off2, off3, off4, off5 = GetFrontMountainOffsets5West();
			PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, off1, off2, off3, true);
			if not DISABLE_FRONT_MOUNTAIN_RIDGES then
				PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, off1, off2, off3, off4, off5, FRONT_MOUNTAIN_BUDGET_DIAGONAL, FRONT_MOUNTAIN_CLUMP_CAP, true);
			end
			if IsSnowWrapX() then
				-- The wrap seam sits at the map edges, not on the tilted
				-- fold, so it uses fixed columns like Standard's does.
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1);
				if not DISABLE_FRONT_MOUNTAIN_RIDGES then
					PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 2, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1, x_wrap_west + 2, FRONT_MOUNTAIN_BUDGET_DIAGONAL, FRONT_MOUNTAIN_CLUMP_CAP);
				end
			end
		elseif cfg.kind == "wetland" then
			local col1, col2, col3, col4, col5 = GetFrontMountainColumns5West(iW);
			PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, col1, col2, col3);
			if not DISABLE_FRONT_MOUNTAIN_RIDGES then
				PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, col1, col2, col3, col4, col5, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
			end
			if IsSnowWrapX() then
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1);
				if not DISABLE_FRONT_MOUNTAIN_RIDGES then
					PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 2, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1, x_wrap_west + 2, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
				end
			end
		elseif cfg.kind == "desert" then
			local col1, col2, col3, col4, col5 = GetFrontMountainColumns5West(iW);
			PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, col1, col2, col3);
			if not DISABLE_FRONT_MOUNTAIN_RIDGES then
				PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, col1, col2, col3, col4, col5, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
			end
			if IsSnowWrapX() then
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PurgeFrontMountainColumns(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1);
				if not DISABLE_FRONT_MOUNTAIN_RIDGES then
					PlaceFrontMountainField(self.wholeworldPlotTypes, iW, iH, x_wrap_west - 2, x_wrap_west - 1, x_wrap_west, x_wrap_west + 1, x_wrap_west + 2, FRONT_MOUNTAIN_BUDGET, FRONT_MOUNTAIN_CLUMP_CAP);
				end
			end
		elseif cfg.chaoticMountains then
			if cfg.kind ~= "tongue" and cfg.kind ~= "bramble" then
				local dens = mountainDensity;
				if cfg.kind == "frosty" then
					dens = dens * 1.28;
					if dens > 0.55 then
						dens = 0.55;
					end
				end
				PlaceChaoticFrontRidge(self.wholeworldPlotTypes, iW, iH, iW / 2 - 4, dens);
			end
			if IsSnowWrapX() then
				local x_wrap_west = GetSnowWrapLandMountainXs(iW);
				PlaceChaoticFrontRidge(self.wholeworldPlotTypes, iW, iH, x_wrap_west, mountainDensity);
			end
		else
			local west_half = {};
			for loop = 1, iH - 2 do
				table.insert(west_half, loop);
			end
			local iNumMountainsPerColumn = math.floor(iH * mountainDensity);

			local front_shuffled = GetShuffledCopyOfTable(west_half)
			local x_west, x_east = iW / 2 - 4, iW / 2 + 3;
			for loop = 1, iNumMountainsPerColumn do
				local y_west, y_east = front_shuffled[loop], iH - 1 - front_shuffled[loop];
				local px_west, px_east = x_west, x_east;
				if IsTiltedMirrorAxis() then
					-- Follow the fold at each mountain's own row instead of a
					-- fixed column, so the "front" ridge tracks the diagonal
					-- barrier instead of cutting straight through it. Vary the
					-- gap to the barrier's edge (0-2 tiles, same roll on both
					-- mirrored sides) instead of always sitting exactly 1 tile
					-- off it.
					local gap = Map.Rand(3, "Front Mountain Gap");
					local _, gapCenterN = ResolveSnowWrapWidths();
					local gapHalf = gapCenterN / 2;
					px_west = TiltedFoldMid(y_west) - (gapHalf + 1 + gap);
					px_east = TiltedFoldMid(y_east) + (gapHalf + gap);
				end
				if px_west >= 0 and px_west < iW then
					self.wholeworldPlotTypes[y_west * iW + px_west + 1] = PlotTypes.PLOT_MOUNTAIN;
				end
				if px_east >= 0 and px_east < iW then
					self.wholeworldPlotTypes[y_east * iW + px_east + 1] = PlotTypes.PLOT_MOUNTAIN;
				end
			end

			if IsSnowWrapX() then
				local wrap_shuffled = GetShuffledCopyOfTable(west_half)
				local x_wrap_west, x_wrap_east = GetSnowWrapLandMountainXs(iW);
				for loop = 1, iNumMountainsPerColumn do
					local y_west, y_east = wrap_shuffled[loop], iH - 1 - wrap_shuffled[loop];
					self.wholeworldPlotTypes[y_west * iW + x_wrap_west + 1] = PlotTypes.PLOT_MOUNTAIN;
					self.wholeworldPlotTypes[y_east * iW + x_wrap_east + 1] = PlotTypes.PLOT_MOUNTAIN;
				end
			end
		end

		-- Interior lakes. At least 3 columns from both snow seams.
		local minX, maxX = GetSnowWrapWaterBounds(iW);
		local function hexNeighbors(x, y)
			if y % 2 == 0 then
				return {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
			end
			return {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
		end
		local minY = 3;
		local maxY = iH - 4;
		local function inLakeRect(x, y)
			if x < minX or x > maxX or y < minY or y > maxY then
				return false
			end
			if IsTiltedMirrorAxis() and WaterAllowedAtXY(x, y) == false then
				return false
			end
			return true
		end
		local function neighborsFit(x, y)
			for _, d in ipairs(hexNeighbors(x, y)) do
				if not inLakeRect(x + d[1], y + d[2]) then
					return false
				end
			end
			return true
		end
		if minX <= maxX and minY <= maxY then
			local nBodies = Map.Rand(4, "Snow Wrap Lake Count");
			if cfg.kind == "desert" then
				nBodies = 0;
			elseif UsesExploCoastShape() then
				local cutIgnored, seas = ResolveSaltWaterPlan();
				nBodies = seas;
			end
			if cfg.kind == "snow" then
				nBodies = 0;
			end
			if cfg.kind == "bramble" then
				-- Bramble's water is entirely PlaceDiagonalBackWater's, not
				-- this generic interior-lake system.
				nBodies = 0;
			end
			if minX > maxX then
				nBodies = 0;
			end
			for n = 1, nBodies do
				local lakeSize = 3 + Map.Rand(8, "Snow Wrap Lake Size");
				local circular = (Map.Rand(2, "Snow Wrap Lake Shape") == 0);
				local wantIsland = circular and lakeSize >= 6 and (Map.Rand(2, "Snow Wrap Lake Island") == 0);
				local seedX, seedY;
				for attempt = 1, 80 do
					local tx = minX + Map.Rand(maxX - minX + 1, "Snow Wrap Lake SeedX");
					local ty = minY + Map.Rand(maxY - minY + 1, "Snow Wrap Lake SeedY");
					local tidx = ty * iW + tx + 1;
					if self.wholeworldPlotTypes[tidx] ~= PlotTypes.PLOT_OCEAN then
						if (not wantIsland) or neighborsFit(tx, ty) then
							seedX, seedY = tx, ty;
							break
						end
					end
				end
				if seedX == nil and wantIsland then
					wantIsland = false;
					for attempt = 1, 80 do
						local tx = minX + Map.Rand(maxX - minX + 1, "Snow Wrap Lake SeedX");
						local ty = minY + Map.Rand(maxY - minY + 1, "Snow Wrap Lake SeedY");
						local tidx = ty * iW + tx + 1;
						if self.wholeworldPlotTypes[tidx] ~= PlotTypes.PLOT_OCEAN then
							seedX, seedY = tx, ty;
							break
						end
					end
				end
				if seedX ~= nil then
					if circular then
						local visited = {};
						local queue = {{seedX, seedY}};
						visited[seedY * iW + seedX] = true;
						local qi = 1;
						local painted = 0;
						while qi <= #queue and painted < lakeSize do
							local cx = queue[qi][1];
							local cy = queue[qi][2];
							qi = qi + 1;
							local skipSeed = wantIsland and cx == seedX and cy == seedY;
							if inLakeRect(cx, cy) then
								local idx = cy * iW + cx + 1;
								if (not skipSeed) and self.wholeworldPlotTypes[idx] ~= PlotTypes.PLOT_OCEAN then
									self.wholeworldPlotTypes[idx] = PlotTypes.PLOT_OCEAN;
									painted = painted + 1;
								end
								for _, d in ipairs(hexNeighbors(cx, cy)) do
									local nx = cx + d[1];
									local ny = cy + d[2];
									local nkey = ny * iW + nx;
									if inLakeRect(nx, ny) and visited[nkey] == nil then
										visited[nkey] = true;
										table.insert(queue, {nx, ny});
									end
								end
							end
						end
					else
						local blob = {{seedX, seedY}};
						self.wholeworldPlotTypes[seedY * iW + seedX + 1] = PlotTypes.PLOT_OCEAN;
						while #blob < lakeSize do
							local candidates = {};
							for _, p in ipairs(blob) do
								for _, d in ipairs(hexNeighbors(p[1], p[2])) do
									local nx = p[1] + d[1];
									local ny = p[2] + d[2];
									if inLakeRect(nx, ny) then
										local idx = ny * iW + nx + 1;
										if self.wholeworldPlotTypes[idx] ~= PlotTypes.PLOT_OCEAN then
											table.insert(candidates, {nx, ny, idx});
										end
									end
								end
							end
							if #candidates == 0 then
								break
							end
							local pick = candidates[Map.Rand(#candidates, "Snow Wrap Lake") + 1];
							self.wholeworldPlotTypes[pick[3]] = PlotTypes.PLOT_OCEAN;
							table.insert(blob, {pick[1], pick[2]});
						end
					end
				end
			end
		end
		if cfg.kind == "desert" then
			PlaceOasisCrescentSeas(self.wholeworldPlotTypes, iW, iH);
		end
		for y = 0, iH - 1 do
			for x = 0, math.floor(iW / 2) - 1 do
				if self.wholeworldPlotTypes[y * iW + x + 1] == PlotTypes.PLOT_OCEAN then
					local mx = iW - x - 1;
					local my = iH - y - 1;
					self.wholeworldPlotTypes[my * iW + mx + 1] = PlotTypes.PLOT_OCEAN;
				end
			end
		end
	end
	if IsSnowNoWrap() then
		if IsOasisClimate() then
			FillOasisWestNoOcean(self.wholeworldPlotTypes, iW, iH);
		elseif IsTiltedMirrorAxis() then
			-- Standard-Diagonal and Bramble both use this (Bramble's water
			-- target/spread was explicitly matched to it -- see
			-- PlaceDiagonalBackWater's own comment).
			PlaceDiagonalBackWater(self.wholeworldPlotTypes, iW, iH);
		else
			ShapeNoWrapBackstrip(self.wholeworldPlotTypes, iW, iH);
		end
	end
	PlaceStandardEdgeSeas(self.wholeworldPlotTypes, iW, iH);
	ConnectInlandSeasToWest(self.wholeworldPlotTypes, iW, iH);
	if backTectonic ~= nil then
		RestoreBackTectonicHills(self.wholeworldPlotTypes, backTectonic, iW, iH);
	end
	-- Plot Type generation completed. Return global plot array.
	return self.wholeworldPlotTypes
end
------------------------------------------------------------------------------
function GeneratePlotTypes()
	print("Setting Plot Types (Lua West vs East) ...");
	WeeveeDbg("GeneratePlotTypes");

	local layered_world = MultilayeredFractal.Create();
	WeeveeDbg("GeneratePlotsByRegion");
	local plot_list = layered_world:GeneratePlotsByRegion();
	WeeveeDbg("GeneratePlotsByRegion done");
	local SplitOps = Map.GetCustomOption(OPT_CENTER_SPLIT);

	SetPlotTypes(plot_list);
	WeeveeDbg("SetPlotTypes done");

	if IsOldSnow() then
		local plot_list = layered_world:GeneratePlotsByRegion();
		local iW, iH = Map.GetGridSize();
		local firstRingYIsEven = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
		local firstRingYIsOdd = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
		for x = iW / 2 - 5, iW / 2 + 4 do
			for y = 1, iH - 2 do
				local plot = Map.GetPlot(x, y)
				if plot:IsFlatlands() then -- Check for adjacent Mountain plot; if found, change this plot to Hills.
					local isEvenY, search_table = true, {};
					if y / 2 > math.floor(y / 2) then
					isEvenY = false;
					end
					if isEvenY then
						search_table = firstRingYIsEven;
					else
						search_table = firstRingYIsOdd;
					end

					for loop, plot_adjustments in ipairs(search_table) do
						local searchX, searchY;
						searchX = x + plot_adjustments[1];
						searchY = y + plot_adjustments[2];
						local searchPlot = Map.GetPlot(searchX, searchY)
						local plotType = searchPlot:GetPlotType()
						if plotType == PlotTypes.PLOT_MOUNTAIN then
							plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false)
							break
						end
					end
				end
			end
		end
	end
	if false then -- Skirmish foothills
		local iW, iH = Map.GetGridSize();
		local firstRingYIsEven = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
		local firstRingYIsOdd = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
		for x = iW / 2 - 2, iW / 2 + 1 do
			for y = 1, iH - 2 do
				local plot = Map.GetPlot(x, y)
				if plot:IsFlatlands() then -- Check for adjacent Mountain plot; if found, change this plot to Hills.
					local isEvenY, search_table = true, {};
					if y / 2 > math.floor(y / 2) then
					isEvenY = false;
					end
					if isEvenY then
						search_table = firstRingYIsEven;
					else
						search_table = firstRingYIsOdd;
					end

					for loop, plot_adjustments in ipairs(search_table) do
						local searchX, searchY;
						searchX = x + plot_adjustments[1];
						searchY = y + plot_adjustments[2];
						local searchPlot = Map.GetPlot(searchX, searchY)
						local plotType = searchPlot:GetPlotType()
						if plotType == PlotTypes.PLOT_MOUNTAIN then
							plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false)
							break
						end
					end
				end
			end
		end
	end
	if IsSnowBarrier() then
		local iW, iH = Map.GetGridSize();
		local firstRingYIsEven = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
		local firstRingYIsOdd = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
		local function applyFoothillAt(x, y, chance)
			local plot = Map.GetPlot(x, y)
			if plot ~= nil and plot:IsFlatlands() then
				local isEvenY, search_table = true, {};
				if y / 2 > math.floor(y / 2) then
					isEvenY = false;
				end
				if isEvenY then
					search_table = firstRingYIsEven;
				else
					search_table = firstRingYIsOdd;
				end
				local nearMtn = false;
				for loop, plot_adjustments in ipairs(search_table) do
					local searchX = x + plot_adjustments[1];
					local searchY = y + plot_adjustments[2];
					local searchPlot = Map.GetPlot(searchX, searchY)
					if searchPlot ~= nil and searchPlot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						nearMtn = true;
						break
					end
				end
				if nearMtn then
					if chance >= 100 or Map.Rand(100, "Front Foothill") < chance then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false)
					end
				end
			end
		end
		local function applyFoothills(xStart, xEnd, chance)
			if chance == nil then
				chance = 100;
			end
			for x = xStart, xEnd do
				for y = 1, iH - 2 do
					applyFoothillAt(x, y, chance)
				end
			end
		end
		local function applyFoothillsNearFold(loOffset, hiOffset, chance)
			if chance == nil then
				chance = 100;
			end
			for y = 1, iH - 2 do
				local mid = TiltedFoldMid(y);
				for x = mid + loOffset, mid + hiOffset do
					applyFoothillAt(x, y, chance)
				end
			end
		end
		-- Inverse of applyFoothillAt: a hill with no mountain in its first
		-- ring has no reason (from this rule's perspective) to be a hill,
		-- so it has a chance to get thinned back down to flat.
		local function applyDehillAt(x, y, chance)
			local plot = Map.GetPlot(x, y)
			if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_HILLS then
				local isEvenY, search_table = true, {};
				if y / 2 > math.floor(y / 2) then
					isEvenY = false;
				end
				if isEvenY then
					search_table = firstRingYIsEven;
				else
					search_table = firstRingYIsOdd;
				end
				local nearMtn = false;
				for loop, plot_adjustments in ipairs(search_table) do
					local searchX = x + plot_adjustments[1];
					local searchY = y + plot_adjustments[2];
					local searchPlot = Map.GetPlot(searchX, searchY)
					if searchPlot ~= nil and searchPlot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						nearMtn = true;
						break
					end
				end
				if nearMtn == false then
					if chance >= 100 or Map.Rand(100, "Front Dehill") < chance then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, false)
					end
				end
			end
		end
		local function applyDehills(xStart, xEnd, chance)
			if chance == nil then
				chance = 100;
			end
			for x = xStart, xEnd do
				for y = 1, iH - 2 do
					applyDehillAt(x, y, chance)
				end
			end
		end
		local function applyDehillsNearFold(loOffset, hiOffset, chance)
			if chance == nil then
				chance = 100;
			end
			for y = 1, iH - 2 do
				local mid = TiltedFoldMid(y);
				for x = mid + loOffset, mid + hiOffset do
					applyDehillAt(x, y, chance)
				end
			end
		end
		local fLo = iW / 2 - 5;
		local fHi = iW / 2 + 4;
		local cfg = GetBarrierConfig();
		local foothillChance = FRONT_FOOTHILL_CHANCE;
		if cfg ~= nil and cfg.kind == "peaks" then
			fLo = iW / 2 - 6;
			fHi = iW / 2 + 5;
			foothillChance = 50;
		elseif cfg ~= nil and cfg.chaoticMountains and IsTiltedMirrorAxis() == false then
			fLo = iW / 2 - 7;
			fHi = iW / 2 + 6;
		end
		if IsBramble() == false then
			if IsTiltedMirrorAxis() then
				applyFoothillsNearFold(fLo - iW / 2, fHi - iW / 2, foothillChance)
				applyDehillsNearFold(fLo - iW / 2, fHi - iW / 2, FRONT_DEHILL_CHANCE)
			else
				applyFoothills(fLo, fHi, foothillChance)
				applyDehills(fLo, fHi, FRONT_DEHILL_CHANCE)
			end
		end
		if IsSnowWrapX() then
			local x_wrap_west, x_wrap_east = GetSnowWrapLandMountainXs(iW);
			local wPad = 1;
			if cfg ~= nil and (cfg.chaoticMountains or cfg.kind == "peaks") then
				wPad = 2;
			end
			applyFoothills(x_wrap_west - wPad, x_wrap_west + wPad, foothillChance)
			applyFoothills(x_wrap_east - wPad, x_wrap_east + wPad, foothillChance)
			applyDehills(x_wrap_west - wPad, x_wrap_west + wPad, FRONT_DEHILL_CHANCE)
			applyDehills(x_wrap_east - wPad, x_wrap_east + wPad, FRONT_DEHILL_CHANCE)
		end
	end

	local args = {bExpandCoasts = false};
	GenerateCoasts(args);
	WeeveeDbg("GeneratePlotTypes done");
end
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
function TerrainGenerator:GetLatitudeAtPlot(iX, iY)
	return GetClimateLatitudeAtPlot(iX, iY);
end
----------------------------------------------------------------------------------
function GenerateTerrain()
	print("Generating Terrain (Lua West vs East) ...");
	WeeveeDbg("GenerateTerrain");
	
	-- Get Temperature setting input by user.
	local temp = DEF_TEMPERATURE;
	if temp == 4 then
		temp = 1 + Map.Rand(3, "Random Temperature - Lua");
	end

	local args = {temperature = temp};
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "desert" then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 1.1;
		args.iDesertPercent = 70;
		args.iPlainsPercent = 36;
		args.fGrassLatitude = 0.26;
		args.fDesertBottomLatitude = 0.66;
		args.fDesertTopLatitude = 1.05;
	elseif cfg ~= nil and cfg.kind == "wasteland" then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 0.0;
		args.iDesertPercent = 0;
		args.iPlainsPercent = 0;
		args.fGrassLatitude = 0.0;
		args.fDesertBottomLatitude = 1.1;
		args.fDesertTopLatitude = 1.1;
	elseif cfg ~= nil and cfg.kind == "wetland" then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 1.1;
		args.iDesertPercent = 0;
		args.iPlainsPercent = 28;
		args.fGrassLatitude = 0.5;
		args.fDesertBottomLatitude = 1.1;
		args.fDesertTopLatitude = 1.1;
	elseif cfg ~= nil and cfg.kind == "peaks" then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 1.1;
		args.iDesertPercent = 0;
		args.iPlainsPercent = 62;
		args.fGrassLatitude = 0.42;
		args.fDesertBottomLatitude = 1.1;
		args.fDesertTopLatitude = 1.1;
	elseif cfg ~= nil and cfg.kind == "frosty" then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 1.1;
		args.iDesertPercent = 0;
		args.iPlainsPercent = 40;
		args.fGrassLatitude = 0.38;
		args.fDesertBottomLatitude = 1.1;
		args.fDesertTopLatitude = 1.1;
	elseif cfg ~= nil and (cfg.kind == "tongue" or cfg.kind == "bramble") then
		args.fSnowLatitude = 1.1;
		args.fTundraLatitude = 1.1;
		args.iDesertPercent = 0;
		args.iPlainsPercent = 45;
		args.fGrassLatitude = 0.55;
		args.fDesertBottomLatitude = 1.1;
		args.fDesertTopLatitude = 1.1;
	end
	local terraingen = TerrainGenerator.Create(args);

	terrainTypes = terraingen:GenerateTerrain();
	
	SetTerrainTypes(terrainTypes);
	WeeveeDbg("SetTerrainTypes done");
	AddMireBands();
	AddPeaksLayout();
	AddFrostyLayout();
	AddBrambleLayout();
	WeeveeDbg("GenerateTerrain done");
end
------------------------------------------------------------------------------



------------------------------------------------------------------------------
function FeatureGenerator:GetLatitudeAtPlot(iX, iY)
	return GetClimateLatitudeAtPlot(iX, iY);
end
------------------------------------------------------------------------------
function FeatureGenerator:AddIceAtPlot(plot, iX, iY, lat)
	return
end
------------------------------------------------------------------------------
function FeatureGenerator:AddJunglesAtPlot(plot, iX, iY, lat)
	local cfg = GetBarrierConfig();
	if cfg ~= nil and (cfg.kind == "wetland" or cfg.kind == "peaks" or cfg.kind == "frosty" or cfg.kind == "tongue" or cfg.kind == "bramble") then
		return
	end
	local jungle_height = self.jungles:GetHeight(iX, iY);
	if jungle_height <= self.iJungleTop and jungle_height >= self.iJungleBottom + (self.iJungleRange * lat) then
		if plot:CanHaveFeature(self.featureJungle) then
			plot:SetFeatureType(self.featureJungle, -1);
		end
	end
end
------------------------------------------------------------------------------
function FeatureGenerator:AddMarshAtPlot(plot, iX, iY, lat)
	local cfg = GetBarrierConfig();
	if cfg ~= nil and (cfg.kind == "wetland" or cfg.kind == "peaks" or cfg.kind == "frosty" or cfg.kind == "tongue" or cfg.kind == "bramble") then
		return
	end
	local marsh_height = self.marsh:GetHeight(iX, iY)
	if marsh_height >= self.iMarshLevel then
		if plot:CanHaveFeature(self.featureMarsh) then
			plot:SetFeatureType(self.featureMarsh, -1)
		end
	end
end
------------------------------------------------------------------------------
function FeatureGenerator:AddForestsAtPlot(plot, iX, iY, lat)
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "wetland" then
		return
	end
	if cfg ~= nil and cfg.kind == "desert" then
		local iW = Map.GetGridSize();
		local skip = FillMireSkip(iW);
		if skip[iX] == true then
			return
		end
	end
	if cfg ~= nil and cfg.kind == "frosty" then
		return
	end
	if cfg ~= nil and (cfg.kind == "tongue" or cfg.kind == "bramble") then
		return
	end
	if cfg ~= nil and cfg.kind == "peaks" then
		local iW = Map.GetGridSize();
		local di = iY * iW + iX + 1;
		local d = peakDist[di];
		local mid = peakMassif[di];
		local fs = 2;
		if mid ~= nil and peakForestStyle[mid] ~= nil then
			fs = peakForestStyle[mid];
		end
		if fs == 3 then
			return
		end
		if d == nil or d < 1 then
			return
		end
		if plot:GetPlotType() ~= PlotTypes.PLOT_HILLS then
			return
		end
		if plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
			return
		end
		local hit = (self.forests:GetHeight(iX, iY) >= self.iForestLevel) or (self.forestclumps:GetHeight(iX, iY) >= self.iClumpLevel);
		if fs == 1 then
			if d ~= 1 then
				return
			end
			if hit == false then
				return
			end
			if Map.Rand(100, "Peaks Forest Spec") >= 34 then
				return
			end
		else
			if d > 3 then
				return
			end
			if hit == false then
				return
			end
		end
		plot:SetFeatureType(self.featureForest, -1)
		return
	end
	if cfg == nil or cfg.kind ~= "wasteland" then
		if (self.forests:GetHeight(iX, iY) >= self.iForestLevel) or (self.forestclumps:GetHeight(iX, iY) >= self.iClumpLevel) then
			if plot:CanHaveFeature(self.featureForest) then
				plot:SetFeatureType(self.featureForest, -1)
			end
		end
		return
	end
	if (self.forests:GetHeight(iX, iY) >= self.iForestLevel) or (self.forestclumps:GetHeight(iX, iY) >= self.iClumpLevel) then
		local t = plot:GetTerrainType();
		if t ~= TerrainTypes.TERRAIN_GRASS and t ~= TerrainTypes.TERRAIN_PLAINS then
			return
		end
		if plot:IsWater() then
			return
		end
		if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			return
		end
		if plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
			return
		end
		plot:SetFeatureType(self.featureForest, -1)
	end
end
------------------------------------------------------------------------------
function FeatureGenerator:AdjustTerrainTypes()
	local cfg = GetBarrierConfig();
	local softenArctic = true;
	if cfg ~= nil and (cfg.kind == "wasteland" or cfg.kind == "wetland" or cfg.kind == "peaks" or cfg.kind == "frosty" or cfg.kind == "tongue" or cfg.kind == "bramble") then
		softenArctic = false;
	end
	local width = self.iGridW - 1;
	local height = self.iGridH - 1;
	local y = 0;
	while y <= height do
		local x = 0;
		while x <= width do
			local plot = Map.GetPlot(x, y);
			if plot:GetFeatureType() == self.featureJungle then
				plot:SetTerrainType(self.terrainPlains, false, true)
			elseif cfg ~= nil and cfg.kind == "frosty" and plot:IsRiver() then
				if plot:GetTerrainType() == self.terrainTundra and FrostyPlotAdjTerrain(plot, TerrainTypes.TERRAIN_SNOW) == false then
					plot:SetTerrainType(self.terrainPlains, false, true)
				end
			elseif softenArctic and plot:IsRiver() then
				local terrainType = plot:GetTerrainType();
				if terrainType == self.terrainTundra then
					plot:SetTerrainType(self.terrainPlains, false, true)
				elseif terrainType == self.terrainIce then
					plot:SetTerrainType(self.terrainTundra, false, true)
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function AddLakes()
	print("Map Generation - Adding Lakes");
	WeeveeDbg("AddLakes");
	local numLakesAdded = 0;
	local iW = Map.GetGridSize();
	local lakePlotRand = 80;
	-- AddLakes runs after AddRivers (rivers must be carved first, or DoRiver's
	-- own IsWater() checks would make them stop short of the coast at the
	-- first lake -- see the ordering comment on GenerateMap). That means a
	-- river's flow was already committed without knowing this plot would
	-- become a lake, so a river edge landing right on a new lake's shore
	-- never actually terminates "into" it, it just runs alongside. Rather
	-- than reorder (which would truncate rivers map-wide) or try to re-stitch
	-- the river afterward, simply never place a lake next to one: checking
	-- only the candidate's own IsRiver() missed a river edge owned by a
	-- neighbor, so check the ring too.
	local function nearRiver(plot)
		if plot:IsRiver() then
			return true
		end
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
			if adj ~= nil and adj:IsRiver() then
				return true
			end
			d = d + 1;
		end
		return false
	end
	for i, plot in Plots() do
		if not plot:IsWater() then
			if not plot:IsCoastalLand() then
				if not nearRiver(plot) then
					local bandRand = lakePlotRand;
					local bi = plot:GetY() * iW + plot:GetX() + 1;
					if mireBand[bi] ~= 3 then
					local r = Map.Rand(bandRand, "MapGenerator AddLakes");
					if r == 0 then
						local allow = true;
						if IsSnowBarrier() then
							if WaterAllowedAtXY(plot:GetX(), plot:GetY()) == false then
								allow = false;
							end
						end
						if allow == true then
							plot:SetArea(-1);
							plot:SetPlotType(PlotTypes.PLOT_OCEAN);
							numLakesAdded = numLakesAdded + 1;
						end
					end
					end
				end
			end
		end
	end
	ScrubWaterNearSnow();
	WeeveeDbg("AddLakes scrub done n=" .. tostring(numLakesAdded));
	if numLakesAdded > 0 then
		print(tostring(numLakesAdded).." lakes added")
		Map.CalculateAreas();
	elseif IsSnowBarrier() then
		Map.CalculateAreas();
	end
end
------------------------------------------------------------------------------
------------------------------------------------------------------------------
function PaintOasisClassicJungle(iW, iH, skip, minX, maxX, frontX, cx, cy, rx, ry, yLo, yHi, maxDy, mid)
	local hinter = OasisWestDesertColumns();
	local placed = {};
	local y = yLo;
	while y <= yHi do
		local yNorm = (y - cy) / maxDy;
		if yNorm < 0 then
			yNorm = 0 - yNorm;
		end
		local xTaper = 1.0 - 0.55 * yNorm;
		if xTaper < 0.35 then
			xTaper = 0.35;
		end
		local x = hinter;
		while x <= frontX do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local plotType = plot:GetPlotType();
					if plotType == PlotTypes.PLOT_LAND or plotType == PlotTypes.PLOT_HILLS then
						local feat = plot:GetFeatureType();
						if feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS and feat ~= FeatureTypes.FEATURE_ICE and feat ~= FeatureTypes.FEATURE_OASIS then
							local nx = (x - cx) / rx;
							if nx < 0 then
								nx = 0 - nx;
							end
							local ny = (y - cy) / ry;
							local d2 = (nx / xTaper) * (nx / xTaper) + ny * ny;
							local jitter = (Map.Rand(21, "Jungle Oval") - 8) / 100;
							local hole = 62;
							if d2 < 0.38 then
								hole = 50;
							end
							if d2 < (1.0 + jitter) and Map.Rand(100, "Jungle Hole") < hole then
								plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
								table.insert(placed, {x, y});
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local pass = 1;
	while pass <= 2 do
		local chance = 16 - pass * 8;
		local nPlaced = #placed;
		local i = 1;
		while i <= nPlaced do
			local px = placed[i][1];
			local py = placed[i][2];
			local yNorm = (py - cy) / maxDy;
			if yNorm < 0 then
				yNorm = 0 - yNorm;
			end
			local taperChance = chance;
			if yNorm > 0.5 then
				taperChance = math.floor(chance * 0.4);
			end
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(px, py, d);
				if adj ~= nil then
					local ax = adj:GetX();
					local ay = adj:GetY();
					if ax >= hinter and ax <= frontX and ay >= yLo and ay <= yHi and skip[ax] ~= true then
						local plotType = adj:GetPlotType();
						if (plotType == PlotTypes.PLOT_LAND or plotType == PlotTypes.PLOT_HILLS)
							and adj:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE
							and adj:GetFeatureType() ~= FeatureTypes.FEATURE_FLOOD_PLAINS
							and adj:GetFeatureType() ~= FeatureTypes.FEATURE_ICE
							and adj:GetFeatureType() ~= FeatureTypes.FEATURE_OASIS then
							if Map.Rand(100, "Jungle Sprawl") < taperChance then
								adj:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								adj:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
								table.insert(placed, {ax, ay});
							end
						end
					end
				end
				d = d + 1;
			end
			i = i + 1;
		end
		pass = pass + 1;
	end
	local nPlaced = #placed;
	local i = 1;
	while i <= nPlaced do
		local px = placed[i][1];
		local py = placed[i][2];
		local tnx = (px - cx) / rx;
		if tnx < 0 then
			tnx = 0 - tnx;
		end
		local tny = (py - cy) / ry;
		if tny < 0 then
			tny = 0 - tny;
		end
		local thin = 14;
		if tnx * tnx + tny * tny < 0.38 then
			thin = 24;
		end
		if Map.Rand(100, "Jungle Thin") < thin then
			local plot = Map.GetPlot(px, py);
			if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				if Map.Rand(100, "Jungle Gap Grass") < 40 then
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
				end
			end
		end
		i = i + 1;
	end
	local playW = frontX - hinter;
	if playW < 8 then
		playW = 8;
	end
	local rxFrame = playW * 0.58 * math.sqrt(0.90);
	local ryFrame = iH * 0.38 * math.sqrt(0.90);
	if rxFrame < 2 then
		rxFrame = 2;
	end
	if ryFrame < 2 then
		ryFrame = 2;
	end
	local landMinX = hinter;
	local landMaxX = mid - 1;
	y = 0;
	while y < iH do
		local yNorm = (y - cy) / maxDy;
		if yNorm < 0 then
			yNorm = 0 - yNorm;
		end
		local xTaper = 1.0 - 0.62 * yNorm;
		if xTaper < 0.35 then
			xTaper = 0.35;
		end
		local x = landMinX;
		while x <= landMaxX do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local plotType = plot:GetPlotType();
					local feat = plot:GetFeatureType();
					if plotType ~= PlotTypes.PLOT_MOUNTAIN
						and plotType ~= PlotTypes.PLOT_OCEAN
						and feat ~= FeatureTypes.FEATURE_JUNGLE
						and feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS
						and feat ~= FeatureTypes.FEATURE_ICE
						and feat ~= FeatureTypes.FEATURE_OASIS then
						local nx = (x - cx) / rxFrame;
						if nx < 0 then
							nx = 0 - nx;
						end
						local ny = (y - cy) / ryFrame;
						local d2 = (nx / xTaper) * (nx / xTaper) + ny * ny;
						local jitter = (Map.Rand(17, "Desert Frame") - 6) / 100;
						local yEdge = (y == 0 or y == iH - 1);
						if yEdge or d2 > (1.0 + jitter) then
							if feat == FeatureTypes.FEATURE_FOREST then
								plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
							end
							plot:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
						elseif plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
							if Map.Rand(100, "Jungle Zone Grass") < 45 then
								plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
							else
								plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	i = 1;
	local rim = {};
	while i <= nPlaced do
		local plot = Map.GetPlot(placed[i][1], placed[i][2]);
		if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(placed[i][1], placed[i][2], d);
				if adj ~= nil then
					local ax = adj:GetX();
					local plotType = adj:GetPlotType();
					if skip[ax] ~= true and ax >= hinter and ax <= frontX
						and (plotType == PlotTypes.PLOT_LAND or plotType == PlotTypes.PLOT_HILLS)
						and adj:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE
						and adj:GetFeatureType() ~= FeatureTypes.FEATURE_FLOOD_PLAINS
						and adj:GetFeatureType() ~= FeatureTypes.FEATURE_ICE
						and adj:GetFeatureType() ~= FeatureTypes.FEATURE_OASIS
						and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
						if Map.Rand(100, "Jungle Rim") < 80 then
							if adj:IsRiver() and Map.Rand(100, "Jungle Rim Grass") < 32 then
								adj:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
							else
								adj:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							end
							table.insert(rim, {ax, adj:GetY()});
						end
					end
				end
				d = d + 1;
			end
		end
		i = i + 1;
	end
	i = 1;
	while i <= #rim do
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(rim[i][1], rim[i][2], d);
			if adj ~= nil then
				local ax = adj:GetX();
				local plotType = adj:GetPlotType();
				if skip[ax] ~= true and ax >= hinter and ax <= frontX
					and (plotType == PlotTypes.PLOT_LAND or plotType == PlotTypes.PLOT_HILLS)
					and adj:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE
					and adj:GetFeatureType() ~= FeatureTypes.FEATURE_FLOOD_PLAINS
					and adj:GetFeatureType() ~= FeatureTypes.FEATURE_ICE
					and adj:GetFeatureType() ~= FeatureTypes.FEATURE_OASIS
					and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					if Map.Rand(100, "Jungle Rim2") < 42 then
						if adj:IsRiver() and Map.Rand(100, "Jungle Rim2 Grass") < 22 then
							adj:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
						else
							adj:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						end
					end
				end
			end
			d = d + 1;
		end
		i = i + 1;
	end
	local nRiverF = 0;
	y = 0;
	while y < iH do
		local x = hinter;
		while x <= frontX do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsRiver() and plot:IsWater() == false then
					local feat = plot:GetFeatureType();
					local ter = plot:GetTerrainType();
					if feat ~= FeatureTypes.FEATURE_JUNGLE
						and feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS
						and feat ~= FeatureTypes.FEATURE_ICE
						and feat ~= FeatureTypes.FEATURE_OASIS
						and (ter == TerrainTypes.TERRAIN_GRASS or ter == TerrainTypes.TERRAIN_PLAINS) then
						if Map.Rand(100, "Oasis Riv F") < 38 then
							plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
							nRiverF = nRiverF + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Desert jungle blob:", #placed, " river forest", nRiverF);
end
------------------------------------------------------------------------------
function OasisGrassHasWater(plot)
	if plot == nil then
		return false
	end
	if plot:IsRiver() or plot:IsFreshWater() or plot:IsWater() then
		return true
	end
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:IsWater() then
			return true
		end
		d = d + 1;
	end
	return false
end
------------------------------------------------------------------------------
function SoftenOasisGrassDesertEdge()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local n = 0;
	local pass = 1;
	while pass <= 2 do
		local hit = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil
						and plot:IsWater() == false
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and plot:GetTerrainType() == TerrainTypes.TERRAIN_GRASS
						and plot:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE
						and OasisGrassHasWater(plot) == false then
						local d = 0;
						local nearDesert = false;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(x, y, d);
							if adj ~= nil and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
								nearDesert = true;
								break
							end
							d = d + 1;
						end
						if nearDesert then
							table.insert(hit, plot);
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local i = 1;
		while i <= #hit do
			if Map.Rand(100, "Oasis Grass Desert") < 82 then
				hit[i]:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
				n = n + 1;
			end
			i = i + 1;
		end
		pass = pass + 1;
	end
	print("Oasis grass-desert to plains:", n);
end
------------------------------------------------------------------------------
function AddDesertJungleBlob()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "desert" then
		return
	end
	WeeveeDbg("AddDesertJungleBlob");
	local iW, iH = Map.GetGridSize();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local ovalW, ovalH, minX, maxX, frontX, cx, cy, rx, ry, yLo, yHi, maxDy, mid = OasisJungleOval(iW, iH);
	if minX > maxX then
		return
	end
	PaintOasisClassicJungle(iW, iH, skip, minX, maxX, frontX, cx, cy, rx, ry, yLo, yHi, maxDy, mid);

	local fp = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:CanHaveFeature(FeatureTypes.FEATURE_FLOOD_PLAINS) then
					plot:SetFeatureType(FeatureTypes.FEATURE_FLOOD_PLAINS, -1);
					fp = fp + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Desert late floodplains:", fp);
	PaintOasisWestDesertBand();
	AddOasisDesertHills();
	SoftenOasisGrassDesertEdge();
	WeeveeDbg("AddDesertJungleBlob done");
end
------------------------------------------------------------------------------
function PaintOasisWestDesertBand()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local band = OasisWestDesertColumns();
	local mid = math.floor(iW / 2);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < band and x <= mid do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:IsWater() == false then
				if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				end
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				plot:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
				n = n + 1;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis west desert band:", n);
	OasisFlattenWestHinterland();
end
------------------------------------------------------------------------------
function OasisFlattenWestHinterland()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if OasisIsWestHinterlandX(x, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local pt = plot:GetPlotType();
					if pt == PlotTypes.PLOT_HILLS or pt == PlotTypes.PLOT_MOUNTAIN then
						local harsh = OasisHinterlandHarshness(x);
						local chance = math.floor(40 + 55 * harsh);
						if Map.Rand(100, "Oasis hinterland flatten") < chance then
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
							n = n + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis hinterland flattened:", n);
end
------------------------------------------------------------------------------
function OasisStripWestHinterlandRivers()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if OasisIsWestHinterlandX(x, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local harsh = OasisHinterlandHarshness(x);
					local chance = math.floor(45 + 55 * harsh);
					if Map.Rand(100, "Oasis hinterland river") < chance then
						plot:SetWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
						plot:SetNWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
						plot:SetNEOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis hinterland rivers stripped:", n);
end
------------------------------------------------------------------------------
function AddOasisDesertHills()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mid = math.floor(iW / 2);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= mid do
			if OasisIsWestHinterlandX(x, iW) == false then
			local plot = Map.GetPlot(x, y);
			if plot ~= nil
				and plot:IsWater() == false
				and plot:GetPlotType() == PlotTypes.PLOT_LAND
				and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
				local feat = plot:GetFeatureType();
				if feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS and feat ~= FeatureTypes.FEATURE_OASIS then
					if Map.Rand(100, "Oasis Desert Hill") < 12 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						n = n + 1;
					end
				end
			end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis desert hills added:", n);
end
------------------------------------------------------------------------------
function StripOasisWestSparseLux()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local band = OasisWestDesertColumns();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2);
	end
	local outside = {};
	local y = 0;
	while y < iH do
		local x = band;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if res ~= nil and res ~= -1 then
					local info = GameInfo.Resources[res];
					if info ~= nil and info.Happiness ~= nil and info.Happiness > 0 then
						if outside[res] == nil then
							outside[res] = 0;
						end
						outside[res] = outside[res] + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local n = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < band and x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if res ~= nil and res ~= -1 then
					local info = GameInfo.Resources[res];
					if info ~= nil and info.Happiness ~= nil and info.Happiness > 0 then
						local have = outside[res];
						if have == nil or have < 2 then
							plot:SetResourceType(-1);
							n = n + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis west sparse lux stripped:", n);
end
------------------------------------------------------------------------------
function StripFrostySnowSparseLux()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2);
	end
	local skip = FillMireSkip(iW);
	local outside = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetTerrainType() ~= TerrainTypes.TERRAIN_SNOW then
					local res = plot:GetResourceType(-1);
					if IsWeeveeLuxuryID(res) then
						if outside[res] == nil then
							outside[res] = 0;
						end
						outside[res] = outside[res] + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local n = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			if skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
					local res = plot:GetResourceType(-1);
					if IsWeeveeLuxuryID(res) then
						local have = outside[res];
						if have == nil or have < 2 then
							plot:SetResourceType(-1);
							n = n + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Frosty snow sparse lux stripped:", n);
end
------------------------------------------------------------------------------
function EnsureOasisUniqueLuxuries()
	if IsOasisClimate() == false then
		return
	end
	local minWant, _, _ = ResolveLuxTargets();
	local iW, iH = Map.GetGridSize();
	local hinter = OasisWestDesertColumns();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2);
	end
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mining = {};
	mining[GameInfoTypes["RESOURCE_GOLD"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_SILVER"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_GEMS"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_COPPER"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_SALT"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_INCENSE"] or -2] = true;
	local miningOrder = {
		GameInfoTypes["RESOURCE_GOLD"],
		GameInfoTypes["RESOURCE_SILVER"],
		GameInfoTypes["RESOURCE_GEMS"],
		GameInfoTypes["RESOURCE_COPPER"],
		GameInfoTypes["RESOURCE_SALT"],
		GameInfoTypes["RESOURCE_INCENSE"],
	};
	local banned = {};
	banned[GameInfoTypes["RESOURCE_JEWELRY"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_PORCELAIN"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_WHALE"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_PEARLS"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_CRAB"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_CORAL"] or -2] = true;
	local seen = {};
	local nUnique = 0;
	local plots = {};
	local desertHills = {};
	local starts = {};
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil then
				table.insert(starts, sp);
			end
		end
		pi = pi + 1;
	end
	local function nearStart(px, py)
		local si = 1;
		while si <= #starts do
			if Map.PlotDistance(px, py, starts[si]:GetX(), starts[si]:GetY()) <= 5 then
				return true
			end
			si = si + 1;
		end
		return false
	end
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			if x >= hinter and skip[x] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local res = plot:GetResourceType(-1);
					if res ~= nil and res ~= -1 then
						local info = GameInfo.Resources[res];
						local lux = false;
						if info ~= nil and info.Happiness ~= nil and info.Happiness > 0 then
							lux = true;
						elseif Game.GetResourceUsageType(res) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY then
							lux = true;
						end
						if lux and seen[res] ~= true then
							seen[res] = true;
							nUnique = nUnique + 1;
						end
					end
					if plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						local feat = plot:GetFeatureType();
						if feat ~= FeatureTypes.FEATURE_ICE then
					if res == nil or res == -1 then
						if nearStart(x, y) == false and OasisLuxuryWithin(x, y, 1) == false then
								table.insert(plots, plot);
								if plot:IsWater() == false
									and plot:GetPlotType() == PlotTypes.PLOT_HILLS
									and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
									table.insert(desertHills, plot);
								end
								end
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local unused = {};
	local unusedMining = {};
	for res in GameInfo.Resources() do
		local lux = false;
		if res.Happiness ~= nil and res.Happiness > 0 then
			lux = true;
		elseif Game.GetResourceUsageType(res.ID) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY then
			lux = true;
		end
		if lux and seen[res.ID] ~= true and banned[res.ID] ~= true then
			if mining[res.ID] == true then
				table.insert(unusedMining, res.ID);
			else
				table.insert(unused, res.ID);
			end
		end
	end
	local mi = 1;
	while mi <= #miningOrder do
		local id = miningOrder[mi];
		if id ~= nil and seen[id] ~= true and banned[id] ~= true then
			local already = false;
			local uj = 1;
			while uj <= #unusedMining do
				if unusedMining[uj] == id then
					already = true;
					break
				end
				uj = uj + 1;
			end
			if already == false then
				table.insert(unusedMining, id);
			end
		end
		mi = mi + 1;
	end
	if #unusedMining > 1 then
		unusedMining = GetShuffledCopyOfTable(unusedMining);
	end
	if #unused > 1 then
		unused = GetShuffledCopyOfTable(unused);
	end
	local queue = {};
	mi = 1;
	while mi <= #unusedMining do
		table.insert(queue, unusedMining[mi]);
		mi = mi + 1;
	end
	mi = 1;
	while mi <= #unused do
		table.insert(queue, unused[mi]);
		mi = mi + 1;
	end
	local nPlaced = 0;
	local qi = 1;
	while qi <= #queue and nUnique < minWant do
		local luxID = queue[qi];
		local placed = false;
		local shuf = plots;
		if #plots > 1 then
			shuf = GetShuffledCopyOfTable(plots);
		end
		local p = 1;
		while p <= #shuf and placed == false do
			local plot = shuf[p];
			if plot:GetResourceType(-1) == -1 and OasisLuxuryWithin(plot:GetX(), plot:GetY(), 1) == false then
				if plot:CanHaveResource(luxID) then
					plot:SetResourceType(luxID, 1);
					placed = true;
				elseif mining[luxID] == true and plot:IsWater() == false then
					local ter = plot:GetTerrainType();
					local feat = plot:GetFeatureType();
					if ter == TerrainTypes.TERRAIN_DESERT
						and feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS
						and feat ~= FeatureTypes.FEATURE_OASIS
						and feat ~= FeatureTypes.FEATURE_JUNGLE then
						if plot:GetPlotType() == PlotTypes.PLOT_LAND then
							plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						end
						if plot:CanHaveResource(luxID) then
							plot:SetResourceType(luxID, 1);
							placed = true;
						end
					end
				elseif mining[luxID] ~= true and plot:IsWater() == false then
					local ter = plot:GetTerrainType();
					local feat = plot:GetFeatureType();
					if ter == TerrainTypes.TERRAIN_DESERT and feat == FeatureTypes.NO_FEATURE then
						if OasisNonDesertLandAdj(plot:GetX(), plot:GetY()) >= 2 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							if plot:CanHaveResource(luxID) then
								plot:SetResourceType(luxID, 1);
								placed = true;
							else
								plot:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
							end
						end
					end
				end
			end
			p = p + 1;
		end
		if placed then
			seen[luxID] = true;
			nUnique = nUnique + 1;
			nPlaced = nPlaced + 1;
		end
		qi = qi + 1;
	end
	local extraWant = 6 + Map.Rand(5, "Oasis Extra Mining");
	local extra = 0;
	if #desertHills > 0 and extraWant > 0 then
		local hills = GetShuffledCopyOfTable(desertHills);
		local hi = 1;
		while hi <= #hills and extra < extraWant do
			local plot = hills[hi];
			if plot:GetResourceType(-1) == -1 and OasisLuxuryWithin(plot:GetX(), plot:GetY(), 1) == false then
				local fit = {};
				mi = 1;
				while mi <= #miningOrder do
					local id = miningOrder[mi];
					if id ~= nil and plot:CanHaveResource(id) then
						table.insert(fit, id);
					end
					mi = mi + 1;
				end
				if nUnique >= minWant then
					local seenFit = {};
					local fi = 1;
					while fi <= #fit do
						if seen[fit[fi]] == true then
							table.insert(seenFit, fit[fi]);
						end
						fi = fi + 1;
					end
					fit = seenFit;
				end
				if #fit > 0 then
					local pick = fit[Map.Rand(#fit, "Oasis Mining Pick") + 1];
					plot:SetResourceType(pick, 1);
					extra = extra + 1;
					if seen[pick] ~= true then
						seen[pick] = true;
						nUnique = nUnique + 1;
					end
				end
			end
			hi = hi + 1;
		end
	end
	print("Oasis unique lux:", nUnique, "min", minWant, "added", nPlaced, "mining extra", extra);
end
------------------------------------------------------------------------------
local LUX_MIN_UNIQUE = 15;
local LUX_MAX_UNIQUE = 24;
local LUX_MIN_DUP = 7;
local LUX_MAX_DUP = 13;
local LUX_MIN_TRIP = 3;
function ResolveLuxTargets()
	if luxTargetResolved then
		return luxWantU, luxWantD, luxWantT;
	end
	luxTargetResolved = true;
	luxWantU = LUX_MIN_UNIQUE + Map.Rand(LUX_MAX_UNIQUE - LUX_MIN_UNIQUE + 1, "Lux unique target");
	luxWantD = LUX_MIN_DUP + Map.Rand(LUX_MAX_DUP - LUX_MIN_DUP + 1, "Lux dup target");
	luxWantT = LUX_MIN_TRIP;
	print("Lux targets unique", luxWantU, "dup", luxWantD, "trip", luxWantT);
	return luxWantU, luxWantD, luxWantT;
end
function IsWeeveeLuxuryID(res)
	if res == nil or res == -1 then
		return false
	end
	local info = GameInfo.Resources[res];
	if info ~= nil and info.Happiness ~= nil and info.Happiness > 0 then
		return true
	end
	return Game.GetResourceUsageType(res) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY;
end
------------------------------------------------------------------------------
-- Shared by every late strip/safety-net pass that used to delete a luxury
-- outright once it landed somewhere no longer legal (barrier column, mountain,
-- a start tile, ...). Moves the resource to a nearby legal tile instead, so a
-- region's already-placed luxury count survives generation instead of just
-- vanishing. `isBanned(x, y)` lets a caller reject candidates inside whatever
-- zone it's enforcing (barrier columns, Bramble separator, ...); every
-- candidate is also barred from landing on any major civ's start plot.
-- Returns false (original tile untouched) only when no legal tile exists
-- within radius -- the caller is still responsible for clearing the original
-- tile itself in that case, a genuine, uncompensated loss.
function TryRelocateLuxury(plot, isBanned, maxRadius)
	if plot == nil then
		return false
	end
	local res = plot:GetResourceType(-1);
	if IsWeeveeLuxuryID(res) == false then
		return false
	end
	local amt = plot:GetNumResource();
	if amt == nil or amt < 1 then
		amt = 1;
	end
	local sx, sy = plot:GetX(), plot:GetY();
	local wasWater = plot:IsWater();
	local radius = maxRadius or 5;
	local cands = {};
	local y = sy - radius;
	while y <= sy + radius do
		local x = sx - radius;
		while x <= sx + radius do
			local d = Map.PlotDistance(sx, sy, x, y);
			if d >= 1 and d <= radius then
				local cand = Map.GetPlot(x, y);
				if cand ~= nil
					and cand:IsWater() == wasWater
					and cand:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and cand:GetResourceType(-1) == -1
					and cand:CanHaveResource(res)
					and PlotIsMajorStart(cand) == false
					and (isBanned == nil or isBanned(x, y) == false) then
					table.insert(cands, cand);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #cands < 1 then
		return false
	end
	if #cands > 1 then
		cands = GetShuffledCopyOfTable(cands);
	end
	cands[1]:SetResourceType(res, amt);
	plot:SetResourceType(-1);
	return true
end
------------------------------------------------------------------------------
function LuxuryPlayableMaxX(iW)
	if DEF_MIRRORED == 1 then
		return math.floor(iW / 2);
	end
	return iW - 1;
end
------------------------------------------------------------------------------
function GatherLuxuryTiers()
	local iW, iH = Map.GetGridSize();
	local maxX = LuxuryPlayableMaxX(iW);
	local counts = {};
	local nUnique = 0;
	local nDup = 0;
	local nTrip = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if IsWeeveeLuxuryID(res) then
					if counts[res] == nil then
						counts[res] = 0;
						nUnique = nUnique + 1;
					end
					counts[res] = counts[res] + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local id, n;
	for id, n in pairs(counts) do
		if n >= 2 then
			nDup = nDup + 1;
		end
		if n >= 3 then
			nTrip = nTrip + 1;
		end
	end
	return counts, nUnique, nDup, nTrip;
end
------------------------------------------------------------------------------
function LuxuryQuotaMet()
	local counts, nUnique, nDup, nTrip = GatherLuxuryTiers();
	local wantU, wantD, wantT = ResolveLuxTargets();
	return (nUnique >= wantU and nDup >= wantD and nTrip >= wantT), nUnique, nDup, nTrip;
end
------------------------------------------------------------------------------
function EnsureLuxuryQuota()
	local banned = {};
	banned[GameInfoTypes["RESOURCE_JEWELRY"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_PORCELAIN"] or -2] = true;
	local iW, iH = Map.GetGridSize();
	local maxX = LuxuryPlayableMaxX(iW);
	local starts = {};
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil then
				table.insert(starts, sp);
			end
		end
		pi = pi + 1;
	end
	local function nearStart(px, py)
		local si = 1;
		while si <= #starts do
			if Map.PlotDistance(px, py, starts[si]:GetX(), starts[si]:GetY()) <= 5 then
				return true
			end
			si = si + 1;
		end
		return false
	end
	local function luxTooClose(px, py, luxID, anyMin, sameMin)
		local y = 0;
		while y < iH do
			local x = 0;
			while x <= maxX do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local res = plot:GetResourceType(-1);
					if IsWeeveeLuxuryID(res) then
						local dist = Map.PlotDistance(px, py, x, y);
						if luxID ~= nil and res == luxID and dist <= sameMin then
							return true
						end
						if dist <= anyMin then
							return true
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		return false
	end
	local function tryPlace(luxID, anyMin, sameMin)
		local cands = {};
		local y = 0;
		while y < iH do
			local skip = RowMireSkip(iW, y);
			local x = 0;
			while x <= maxX do
				if skip[x] ~= true and nearStart(x, y) == false then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and plot:GetResourceType(-1) == -1
						and plot:CanHaveResource(luxID)
						and luxTooClose(x, y, luxID, anyMin, sameMin) == false then
						local cfgLux = GetBarrierConfig();
						if not (cfgLux ~= nil and cfgLux.kind == "frosty" and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW) then
							table.insert(cands, plot);
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands < 1 then
			return false
		end
		if #cands > 1 then
			cands = GetShuffledCopyOfTable(cands);
		end
		cands[1]:SetResourceType(luxID, 1);
		return true
	end
	local function tryPlaceHard(luxID, anyMin, sameMin)
		if tryPlace(luxID, anyMin, sameMin) then
			return true
		end
		local cands = {};
		local y = 0;
		while y < iH do
			local skip = RowMireSkip(iW, y);
			local x = 0;
			while x <= maxX do
				if skip[x] ~= true and nearStart(x, y) == false then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil
						and plot:IsWater() == false
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and plot:GetResourceType(-1) == -1
						and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT
						and luxTooClose(x, y, luxID, anyMin, sameMin) == false then
						table.insert(cands, plot);
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands < 1 then
			return false
		end
		if #cands > 1 then
			cands = GetShuffledCopyOfTable(cands);
		end
		local i = 1;
		while i <= #cands do
			local plot = cands[i];
			local feat = plot:GetFeatureType();
			if feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS and feat ~= FeatureTypes.FEATURE_OASIS and feat ~= FeatureTypes.FEATURE_JUNGLE then
				local oldType = plot:GetPlotType();
				if oldType == PlotTypes.PLOT_LAND then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				end
				if plot:CanHaveResource(luxID) then
					plot:SetResourceType(luxID, 1);
					return true
				end
				if oldType == PlotTypes.PLOT_LAND then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
				if feat == FeatureTypes.NO_FEATURE and OasisNonDesertLandAdj(plot:GetX(), plot:GetY()) >= 2 then
					plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
					if plot:CanHaveResource(luxID) then
						plot:SetResourceType(luxID, 1);
						return true
					end
					plot:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
				end
			end
			i = i + 1;
		end
		return false
	end
	local function tryPlaceForceTriplicate(luxID)
		-- Non-desert-specific hard fallback for Standard-Diagonal: relax the
		-- spacing rules progressively, then as a last resort convert a plain
		-- land plot to hills to open up hill-locked resources. Deliberately
		-- separate from tryPlaceHard (which stays desert-terrain-specific for
		-- Oasis) so Oasis's placement behavior is untouched.
		if tryPlace(luxID, 1, 2) then
			return true
		end
		if tryPlace(luxID, 0, 0) then
			return true
		end
		local cands = {};
		local y = 0;
		while y < iH do
			local skip = RowMireSkip(iW, y);
			local x = 0;
			while x <= maxX do
				if skip[x] ~= true and nearStart(x, y) == false then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil
						and plot:IsWater() == false
						and plot:GetPlotType() == PlotTypes.PLOT_LAND
						and plot:GetResourceType(-1) == -1 then
						table.insert(cands, plot);
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands > 1 then
			cands = GetShuffledCopyOfTable(cands);
		end
		local i = 1;
		while i <= #cands do
			local plot = cands[i];
			plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			if plot:CanHaveResource(luxID) then
				plot:SetResourceType(luxID, 1);
				return true
			end
			plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
			i = i + 1;
		end
		return false
	end
	local function padTo(needCount, fromCount, targetHave)
		local counts = GatherLuxuryTiers();
		local ids = {};
		local id, n;
		for id, n in pairs(counts) do
			if n == fromCount and banned[id] ~= true then
				table.insert(ids, id);
			end
		end
		if #ids > 1 then
			ids = GetShuffledCopyOfTable(ids);
		end
		local have = 0;
		for id, n in pairs(counts) do
			if n >= needCount then
				have = have + 1;
			end
		end
		local i = 1;
		while have < targetHave and i <= #ids do
			if tryPlace(ids[i], 3, 5) or tryPlace(ids[i], 2, 4) then
				have = have + 1;
			end
			i = i + 1;
		end
	end
	local counts, nUnique, nDup, nTrip = GatherLuxuryTiers();
	local wantU, wantD, wantT = ResolveLuxTargets();
	if IsOasisClimate() and nUnique < wantU then
		local unused = {};
		for res in GameInfo.Resources() do
			if IsWeeveeLuxuryID(res.ID) and counts[res.ID] == nil and banned[res.ID] ~= true then
				table.insert(unused, res.ID);
			end
		end
		if #unused > 1 then
			unused = GetShuffledCopyOfTable(unused);
		end
		local ui = 1;
		while nUnique < wantU and ui <= #unused do
			if tryPlaceHard(unused[ui], 3, 5) or tryPlaceHard(unused[ui], 2, 4) then
				nUnique = nUnique + 1;
			end
			ui = ui + 1;
		end
	elseif nUnique < wantU then
		-- Every non-Oasis climate, plain Standard included, reaches for the
		-- same randomized ideal target (LUX_MIN_UNIQUE..LUX_MAX_UNIQUE)
		-- instead of Standard settling for the bare floor -- Standard no
		-- longer gets a floor-only carve-out (see LuxuryQuotaMet's matching
		-- removal of its own Standard exemption, so a Standard roll that
		-- falls short now rerolls the whole map like every other climate).
		local unused = {};
		for res in GameInfo.Resources() do
			if IsWeeveeLuxuryID(res.ID) and counts[res.ID] == nil and banned[res.ID] ~= true then
				table.insert(unused, res.ID);
			end
		end
		if #unused > 1 then
			unused = GetShuffledCopyOfTable(unused);
		end
		local ui = 1;
		while nUnique < wantU and ui <= #unused do
			if tryPlace(unused[ui], 3, 5) or tryPlace(unused[ui], 2, 4) then
				nUnique = nUnique + 1;
			end
			ui = ui + 1;
		end
	end
	padTo(2, 1, wantD);
	padTo(3, 2, wantT);
	if IsStandardClimate() and IsTiltedMirrorAxis() then
		-- Standard-Diagonal treats a triplicate shortfall as serious: force one
		-- through with relaxed spacing/terraforming before falling back to a
		-- full map reroll (GenerateMap retries on LuxuryQuotaMet() == false).
		local counts2 = GatherLuxuryTiers();
		local dupIds = {};
		local id2, n2;
		for id2, n2 in pairs(counts2) do
			if n2 == 2 and banned[id2] ~= true then
				table.insert(dupIds, id2);
			end
		end
		if #dupIds > 1 then
			dupIds = GetShuffledCopyOfTable(dupIds);
		end
		local haveT = 0;
		for id2, n2 in pairs(counts2) do
			if n2 >= 3 then
				haveT = haveT + 1;
			end
		end
		local fi = 1;
		while haveT < wantT and fi <= #dupIds do
			if tryPlaceForceTriplicate(dupIds[fi]) then
				haveT = haveT + 1;
			end
			fi = fi + 1;
		end
	end
	local ok, u, d, t = LuxuryQuotaMet();
	print("Luxury quota pad:", u, "/", wantU, "unique", d, "/", wantD, "dup", t, "/", wantT, "trip", "ok", tostring(ok));
	-- print() isn't captured anywhere persistent in this setup (Lua.log stays
	-- essentially empty) -- this is called twice per generation (once in the
	-- normal pipeline, again as "EnsureLuxuryQuota-postRegionalForce" at the
	-- very end), so the first logged line per roll is the pre-regional-force
	-- snapshot and the second is the true final state.
	WeeveeDbgPersist("EnsureLuxuryQuota unique=" .. u .. "/" .. wantU .. " dup=" .. d .. "/" .. wantD .. " trip=" .. t .. "/" .. wantT .. " ok=" .. tostring(ok));
	return ok
end
------------------------------------------------------------------------------
-- EnsureLuxuryQuota only ever pads upward toward the rolled unique/dup/trip
-- targets, never trims. That was fine when the targets were the only thing
-- driving these counts, but EnsureRegionalLuxuryTarget's guaranteed 3
-- regional types (each forced to ~5-7 copies) structurally push all three
-- counts up by construction, on top of whatever the roll actually wanted --
-- and since nothing ever removes anything, the map's overall luxury density
-- can only ratchet upward roll after roll, making a roll that lands at the
-- low end of the accepted ranges (e.g. exactly 3 triplicates) effectively
-- impossible even when that's what got rolled. Runs last, once every other
-- luxury pass is done: trims non-regional (and non-Marble) excess back down
-- toward the actual rolled target, one category at a time (triplicate
-- first, since reducing a triplicate-tier type can also resolve dup/unique
-- overshoot as a side effect, then duplicate, then unique), always removing
-- from whichever type sits at the bare minimum for that tier (count exactly
-- 3, 2, or 1) so a type far above threshold is never touched. The 3
-- guaranteed regional types are never eligible -- this only ever removes
-- the count OTHER passes (random/city-state placement, or padding) added
-- beyond what the roll's own target called for.
function TrimLuxuryQuotaExcess(asp)
	if asp == nil or asp.region_luxury_assignment == nil then
		return
	end
	local wantU, wantD, wantT = ResolveLuxTargets();
	local counts, nUnique, nDup, nTrip = GatherLuxuryTiers();
	local protected = {};
	local rn = 1;
	while rn <= asp.iNumCivs do
		local lid = asp.region_luxury_assignment[rn];
		if lid ~= nil then
			protected[lid] = true;
		end
		rn = rn + 1;
	end
	if asp.marble_ID ~= nil then
		protected[asp.marble_ID] = true;
	end
	local iW, iH = Map.GetGridSize();
	local maxX = LuxuryPlayableMaxX(iW);
	local function removeOneCopy(resID)
		local y = 0;
		while y < iH do
			local x = 0;
			while x <= maxX do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetResourceType(-1) == resID then
					plot:SetResourceType(-1);
					return true
				end
				x = x + 1;
			end
			y = y + 1;
		end
		return false
	end
	local nTrimmed = 0;
	-- nTrip (from GatherLuxuryTiers) counts every type with >=3 copies, not
	-- just ones sitting at exactly 3 -- picking only an exact-3 match here
	-- meant a non-regional type that already had 4+ copies (vanilla
	-- placement, city-state seeding, or EnsureLuxuryQuota padding landing on
	-- it) could never be selected at all, so it sat there inflating nTrip
	-- forever with nothing ever trimming it back out of the tier. Instead,
	-- pick whichever unprotected type still in the tier has the LOWEST
	-- count -- for a type already at exactly 3 this behaves identically to
	-- before (one removal drops it out immediately); for a leftover 4/5/6+
	-- copy type it gets walked down one copy per loop iteration until it
	-- finally drops below 3 and actually exits the tier.
	while nTrip > wantT do
		local target, targetN = nil, nil;
		local resID, n;
		for resID, n in pairs(counts) do
			if n >= 3 and protected[resID] ~= true and (targetN == nil or n < targetN) then
				target, targetN = resID, n;
			end
		end
		if target == nil or removeOneCopy(target) == false then
			break
		end
		counts[target] = counts[target] - 1;
		if counts[target] < 3 then
			nTrip = nTrip - 1;
		end
		nTrimmed = nTrimmed + 1;
	end
	while nDup > wantD do
		local target = nil;
		local resID, n;
		for resID, n in pairs(counts) do
			if n == 2 and protected[resID] ~= true then
				target = resID;
				break
			end
		end
		if target == nil or removeOneCopy(target) == false then
			break
		end
		counts[target] = counts[target] - 1;
		nDup = nDup - 1;
		nTrimmed = nTrimmed + 1;
	end
	while nUnique > wantU do
		local target = nil;
		local resID, n;
		for resID, n in pairs(counts) do
			if n == 1 and protected[resID] ~= true then
				target = resID;
				break
			end
		end
		if target == nil or removeOneCopy(target) == false then
			break
		end
		counts[target] = nil;
		nUnique = nUnique - 1;
		nTrimmed = nTrimmed + 1;
	end
	WeeveeDbgPersist("TrimLuxuryQuotaExcess trimmed=" .. nTrimmed .. " final unique=" .. nUnique .. "/" .. wantU .. " dup=" .. nDup .. "/" .. wantD .. " trip=" .. nTrip .. "/" .. wantT);
end
------------------------------------------------------------------------------
function EnsureStartLuxuryFloor()
	local want = 3;
	local maxD = 3;
	local banned = {};
	banned[GameInfoTypes["RESOURCE_JEWELRY"] or -2] = true;
	banned[GameInfoTypes["RESOURCE_PORCELAIN"] or -2] = true;
	local mining = {};
	mining[GameInfoTypes["RESOURCE_GOLD"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_SILVER"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_GEMS"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_COPPER"] or -2] = true;
	mining[GameInfoTypes["RESOURCE_SALT"] or -2] = true;
	local iW, iH = Map.GetGridSize();
	local function tryPut(plot, luxID)
		if plot == nil or luxID == nil or banned[luxID] == true then
			return false
		end
		if plot:GetResourceType(-1) ~= -1 then
			return false
		end
		if plot:CanHaveResource(luxID) then
			plot:SetResourceType(luxID, 1);
			return true
		end
		if mining[luxID] == true and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
			local feat = plot:GetFeatureType();
			if feat ~= FeatureTypes.FEATURE_FLOOD_PLAINS and feat ~= FeatureTypes.FEATURE_OASIS and feat ~= FeatureTypes.FEATURE_JUNGLE and feat ~= FeatureTypes.FEATURE_ICE then
				local oldType = plot:GetPlotType();
				if oldType == PlotTypes.PLOT_LAND then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				end
				if plot:CanHaveResource(luxID) then
					plot:SetResourceType(luxID, 1);
					return true
				end
				if oldType == PlotTypes.PLOT_LAND then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
			end
		end
		return false
	end
	local nPad = 0;
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil then
				local sx = sp:GetX();
				local sy = sp:GetY();
				local have = {};
				local nHave = 0;
				local cands = {};
				local y = sy - maxD;
				while y <= sy + maxD do
					local x = sx - maxD;
					while x <= sx + maxD do
						local d = Map.PlotDistance(sx, sy, x, y);
						if d >= 1 and d <= maxD then
							local plot = Map.GetPlot(x, y);
							if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
								local res = plot:GetResourceType(-1);
								if IsWeeveeLuxuryID(res) then
									if have[res] == nil then
										have[res] = 0;
									end
									have[res] = have[res] + 1;
									nHave = nHave + 1;
								elseif res == nil or res == -1 then
									local feat = plot:GetFeatureType();
									if feat ~= FeatureTypes.FEATURE_ICE then
										table.insert(cands, plot);
									end
								end
							end
						end
						x = x + 1;
					end
					y = y + 1;
				end
				if nHave < want and #cands > 0 then
					if #cands > 1 then
						cands = GetShuffledCopyOfTable(cands);
					end
					local idsNew = {};
					local idsHave = {};
					local idsAny = {};
					for res in GameInfo.Resources() do
						if IsWeeveeLuxuryID(res.ID) and banned[res.ID] ~= true then
							table.insert(idsAny, res.ID);
							if have[res.ID] == nil then
								table.insert(idsNew, res.ID);
							else
								table.insert(idsHave, res.ID);
							end
						end
					end
					local bags = {idsNew, idsHave, idsAny};
					local b = 1;
					while nHave < want and b <= #bags do
						local ids = bags[b];
						if #ids > 1 then
							ids = GetShuffledCopyOfTable(ids);
						end
						local ii = 1;
						while nHave < want and ii <= #ids do
							local luxID = ids[ii];
							local ci = 1;
							while nHave < want and ci <= #cands do
								if tryPut(cands[ci], luxID) then
									nHave = nHave + 1;
									nPad = nPad + 1;
									if have[luxID] == nil then
										have[luxID] = 0;
									end
									have[luxID] = have[luxID] + 1;
								end
								ci = ci + 1;
							end
							ii = ii + 1;
						end
						b = b + 1;
					end
				end
				print("Start lux floor civ", pi, "have", nHave, "want", want);
			end
		end
		pi = pi + 1;
	end
	print("Start luxury floor added:", nPad);
end
------------------------------------------------------------------------------
-- Vanilla's own region-wide/start-tile luxury placement (inside
-- PlaceResourcesAndCityStates) tracks its own shortfall internally
-- (PlaceSpecificNumberOfResources returns how many of a target amount it
-- couldn't place) but only logs that number and gives up once its own
-- primary/secondary/tertiary/quaternary plot-list tiers run dry -- on a
-- Small map with few civs those tiers are often too thin to reach vanilla's
-- own target. Runs last, once every start plot is final and every other
-- strip/cap pass has already had its say: recomputes each west region's
-- actual on-map count of its assigned regional luxury from scratch and, for
-- any shortfall, forces the rest into a plot -- empty tiles first, and only
-- "bouncing" (evicting, relocating first if the occupant is itself a
-- luxury) an occupied one if no empty legal tile is left, then a legalizing
-- edit (see tryTerraformPlace) as a final resort.
--
-- Deliberately never touches anything within radius 3 of any capital.
-- Vanilla's own start-tile pass plus EnsureStartLuxuryFloor already reliably
-- build the classic 3 (regional) + 1 (other) near-capital pattern on their
-- own, before this function ever runs -- an earlier version of this
-- function also tried to manage that ring directly (force/bounce/trim/retry
-- toward a "3 near" guarantee) and that was the wrong call: it kept
-- introducing new near-capital problems (overshoot, undershoot, cross-region
-- collateral damage) in territory that was already working. This only tops
-- up the region-wide total from outside that ring, so it can only ever add
-- to what vanilla already built near the capital, never rearrange it.
--
-- Region-independent by design otherwise: it never consults the region's own
-- plot-list machinery, just raw proximity to the capital, so a thin/oddly
-- shaped region can't starve it the way vanilla's tiered lists can. Global
-- unique/dup/triplicate ranges get disrupted by the bouncing, so the caller
-- is expected to run EnsureLuxuryQuota() again afterward to rebalance.
function EnsureRegionalLuxuryTarget(asp)
	if asp == nil or asp.region_luxury_assignment == nil or asp.player_ID_list == nil then
		return
	end
	local radius = 6;
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2) - 1;
	end
	local function inBarrier(x, y)
		local skip = RowMireSkip(iW, y);
		return skip[x] == true;
	end
	-- This function's whole search only ever operates at radius 4 and
	-- beyond (see the "never touch the near ring" note below), which can
	-- still reach out far enough to overlap a neighboring civ's own
	-- radius-3 ring when starts are close to the 7-tile minimum spacing.
	-- Never touch a tile within `buf` of ANY capital, ours or someone
	-- else's -- radius 4+ can never be within 3 of the capital doing the
	-- searching anyway, so no "own capital" exception is needed. `buf`
	-- defaults to 3 (exactly the other capital's own ring) for the normal-
	-- range search; the far-reaching escalation/terraform tiers pass a
	-- wider buffer (5) so a placement that has to travel that far doesn't
	-- end up reading as "sitting right next to a different player's stuff"
	-- even though it's technically outside their strict ring.
	local function nearAnyCapital(x, y, buf)
		buf = buf or 3;
		local pi = 0;
		while pi < GameDefines.MAX_MAJOR_CIVS do
			local p = Players[pi];
			if p ~= nil and p:IsAlive() then
				local otherSp = p:GetStartingPlot();
				if otherSp ~= nil and Map.PlotDistance(x, y, otherSp:GetX(), otherSp:GetY()) <= buf then
					return true
				end
			end
			pi = pi + 1;
		end
		return false
	end
	-- Vanilla's own region-wide scatter (PlaceSpecificNumberOfResources)
	-- keeps same-type luxuries a few tiles apart via its "impact table"
	-- spacing system -- our forcing bypasses that machinery entirely (it
	-- just calls SetResourceType directly), so without an equivalent check
	-- here, several forced copies of the same resource can land shoulder to
	-- shoulder wherever the only eligible land happens to be, reading as an
	-- unnaturally dense cluster instead of a spread-out region-wide total.
	local function tooCloseToSame(x, y, resID, minDist)
		local yy = y - minDist;
		while yy <= y + minDist do
			local xx = x - minDist;
			while xx <= x + minDist do
				if Map.PlotDistance(x, y, xx, yy) < minDist then
					local plot = Map.GetPlot(xx, yy);
					if plot ~= nil and plot:GetResourceType(-1) == resID then
						return true
					end
				end
				xx = xx + 1;
			end
			yy = yy + 1;
		end
		return false
	end
	local counts = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if res ~= -1 then
					counts[res] = (counts[res] or 0) + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	-- A tile holding ANY region's assigned regional luxury is off-limits as
	-- a bounce/terraform source for every OTHER region's search -- without
	-- this, a later region's wide Phase 2/escalation reach (radius up to
	-- `radius`+3, easily overlapping a neighbor 7-9 tiles away) can evict an
	-- earlier region's already-correctly-placed copy as collateral, and if
	-- the eviction's own relocation attempt fails, delete it outright with
	-- no bookkeeping update for the region that already finished processing.
	-- That's what caused final counts reported here to disagree with the
	-- fresh recount taken afterward in LogRegionalLuxuryCounts.
	local allRegionalLuxIDs = {};
	do
		local rn = 1;
		while rn <= asp.iNumCivs do
			local lid = asp.region_luxury_assignment[rn];
			if lid ~= nil then
				allRegionalLuxIDs[lid] = true;
			end
			rn = rn + 1;
		end
	end
	local function regionalTarget(region_number, resID)
		local target_list = asp:GetRegionLuxuryTargetNumbers();
		local base = 0;
		if target_list ~= nil and target_list[asp.iNumCivs] ~= nil then
			base = target_list[asp.iNumCivs];
		end
		local split = 1;
		if asp.luxury_assignment_count ~= nil and asp.luxury_assignment_count[resID] ~= nil and asp.luxury_assignment_count[resID] > 0 then
			split = asp.luxury_assignment_count[resID];
		end
		local fertBonus = 0;
		if asp.luxury_low_fert_compensation ~= nil and asp.luxury_low_fert_compensation[resID] ~= nil then
			fertBonus = 0.5 * asp.luxury_low_fert_compensation[resID];
		end
		-- Vanilla subtracts region_low_fert_compensation here because ITS
		-- start-tile pass already added that same amount on top of the flat
		-- 2/3 base (a poor region gets extra copies at the capital instead of
		-- in the region-wide scatter). Our `atStart` below stays flat at the
		-- base, never adding that compensation back in, so subtracting it a
		-- second time here would double-count the deduction and undershoot
		-- vanilla's true total (this was exactly the earlier 5/7 bug: targets
		-- landing on 5 or 7 instead of a stable 6 whenever a region rolled a
		-- fertility bonus). Leaving it out here makes the two sides cancel
		-- correctly, matching vanilla's actual (start + region-wide) total.
		local regionWide = math.floor((base + fertBonus) / split);
		regionWide = regionWide - 1;
		if asp.resource_setting == 1 then
			regionWide = regionWide - 1;
		elseif asp.resource_setting == 3 then
			regionWide = regionWide + 2;
		end
		regionWide = math.max(2, regionWide);
		local atStart = 2;
		if asp.resource_setting == 4 then
			atStart = 3;
		end
		return regionWide + atStart;
	end
	local function tryBounce(sp, resID, minRadius, maxRadius, neighborBuf)
		local sx, sy = sp:GetX(), sp:GetY();
		local emptyCands, occupiedCands = {}, {};
		local yy = sy - maxRadius;
		while yy <= sy + maxRadius do
			local xx = sx - maxRadius;
			while xx <= sx + maxRadius do
				local d = Map.PlotDistance(sx, sy, xx, yy);
				if d >= minRadius and d <= maxRadius then
					local plot = Map.GetPlot(xx, yy);
					if plot ~= nil
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and PlotIsMajorStart(plot) == false
						and inBarrier(xx, yy) == false
						and nearAnyCapital(xx, yy, neighborBuf) == false
						and tooCloseToSame(xx, yy, resID, 2) == false
						and plot:CanHaveResource(resID) then
						local existingRes = plot:GetResourceType(-1);
						if existingRes == -1 then
							table.insert(emptyCands, plot);
						elseif existingRes ~= resID and allRegionalLuxIDs[existingRes] ~= true then
							table.insert(occupiedCands, plot);
						end
					end
				end
				xx = xx + 1;
			end
			yy = yy + 1;
		end
		if #emptyCands > 0 then
			if #emptyCands > 1 then
				emptyCands = GetShuffledCopyOfTable(emptyCands);
			end
			emptyCands[1]:SetResourceType(resID, 1);
			return true
		end
		if #occupiedCands < 1 then
			return false
		end
		if #occupiedCands > 1 then
			occupiedCands = GetShuffledCopyOfTable(occupiedCands);
		end
		local bounced = occupiedCands[1];
		if IsWeeveeLuxuryID(bounced:GetResourceType(-1)) then
			-- Keep the displaced luxury out of every capital's own ring --
			-- with no exclusion here its relocation search could land right
			-- back inside one, planting a stray foreign type into a spawn
			-- cluster that never needed touching.
			local function banNearCapitalOrBarrier(x, y)
				return inBarrier(x, y) or nearAnyCapital(x, y, neighborBuf);
			end
			TryRelocateLuxury(bounced, banNearCapitalOrBarrier, radius + 6);
		end
		if bounced:GetResourceType(-1) ~= -1 then
			bounced:SetResourceType(-1);
		end
		bounced:SetResourceType(resID, 1);
		return true
	end
	local function countNear(sp, resID, r)
		local sx, sy = sp:GetX(), sp:GetY();
		local n = 0;
		local yy = sy - r;
		while yy <= sy + r do
			local xx = sx - r;
			while xx <= sx + r do
				if Map.PlotDistance(sx, sy, xx, yy) <= r then
					local plot = Map.GetPlot(xx, yy);
					if plot ~= nil and plot:GetResourceType(-1) == resID then
						n = n + 1;
					end
				end
				xx = xx + 1;
			end
			yy = yy + 1;
		end
		return n;
	end
	-- Every terrain and feature the ruleset itself says legalizes resID,
	-- queried straight from the loaded data instead of a hardcoded guess --
	-- this covers any luxury (including modded ones like Amber/Jade/Lapis/
	-- Obsidian) automatically, without needing to know its specific
	-- requirement in advance. Results are cached per resID since the
	-- underlying tables never change mid-generation.
	local terrainCache, featureCache = {}, {};
	local function resourceLegalTerrains(resID)
		if terrainCache[resID] ~= nil then
			return terrainCache[resID]
		end
		local list = {};
		local resType = GameInfo.Resources[resID] and GameInfo.Resources[resID].Type;
		if resType ~= nil then
			for row in GameInfo.Resource_TerrainBooleans() do
				if row.ResourceType == resType then
					local t = GameInfoTypes[row.TerrainType];
					if t ~= nil then
						table.insert(list, t);
					end
				end
			end
		end
		terrainCache[resID] = list;
		return list
	end
	local function resourceLegalFeatures(resID)
		if featureCache[resID] ~= nil then
			return featureCache[resID]
		end
		local list = {};
		local resType = GameInfo.Resources[resID] and GameInfo.Resources[resID].Type;
		if resType ~= nil then
			for row in GameInfo.Resource_FeatureBooleans() do
				if row.ResourceType == resType then
					local f = GameInfoTypes[row.FeatureType];
					if f ~= nil then
						table.insert(list, f);
					end
				end
			end
		end
		featureCache[resID] = list;
		return list
	end
	local function plotLatitude(y)
		return math.abs((iH / 2) - y) / (iH / 2);
	end
	-- Last resort, tried only once every plain bounce/escalation attempt has
	-- already failed: legalize an otherwise-unusable tile by editing it,
	-- mirroring the precedent already set elsewhere in this file
	-- (EnsureLuxuryQuota's tryPlaceHard/tryPlaceForceTriplicate convert plot
	-- type to hills for the same reason). Tries every legalizing edit for
	-- resID on a single plot, in place, leaving the edit applied on success
	-- or fully reverted on failure. Hills stays a separate first try (plot
	-- type, not covered by Resource_TerrainBooleans) and is unrestricted.
	-- Every OTHER terrain/feature comes from the ruleset's own legal list
	-- for resID; Tundra and Snow (terrain) and Jungle (feature) are the only
	-- climate-sensitive ones in this ruleset, so those are skipped unless
	-- the tile's own latitude already fits (poleward for Tundra/Snow,
	-- equatorial for Jungle) -- a rescue edit should never paint jungle near
	-- a pole or tundra onto a tropical tile. Everything else the ruleset
	-- allows (Forest, Marsh, Desert, Plains, Oasis, Flood Plains, ...) is
	-- tried unrestricted.
	local function tryTerraformOnPlot(plot, resID)
		if plot:GetPlotType() == PlotTypes.PLOT_LAND then
			plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			if plot:CanHaveResource(resID) then
				return true
			end
			plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		end
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			local oldTerrain = plot:GetTerrainType();
			local terrains = resourceLegalTerrains(resID);
			local ti = 1;
			while ti <= #terrains do
				local t = terrains[ti];
				if t ~= oldTerrain then
					local isPolar = (t == TerrainTypes.TERRAIN_TUNDRA or t == TerrainTypes.TERRAIN_SNOW);
					if (isPolar == false) or (plotLatitude(plot:GetY()) > 0.5 and ClimateAllowsInteriorPolarTerrain()) then
						plot:SetTerrainType(t, false, false);
						if plot:CanHaveResource(resID) then
							return true
						end
						plot:SetTerrainType(oldTerrain, false, false);
					end
				end
				ti = ti + 1;
			end
		end
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			local features = resourceLegalFeatures(resID);
			local fi = 1;
			while fi <= #features do
				local f = features[fi];
				local isJungle = (f == FeatureTypes.FEATURE_JUNGLE);
				-- Forest, like Hills above, is climate-neutral enough in
				-- this ruleset to plant regardless of the tile's terrain --
				-- CanHaveFeature would refuse it on Desert/Snow specifically,
				-- but CanHaveResource right below is the gate that actually
				-- matters, and reverts it immediately if it didn't help.
				-- Every other feature keeps the normal CanHaveFeature check
				-- (Flood Plains needs river adjacency, Oasis has its own
				-- rules, etc. -- forcing those regardless would risk a
				-- genuinely broken-looking tile, not just an unusual one).
				local isForest = (f == FeatureTypes.FEATURE_FOREST);
				if ((isJungle == false) or plotLatitude(plot:GetY()) < 0.5) and (isForest or plot:CanHaveFeature(f)) then
					plot:SetFeatureType(f, -1);
					if plot:CanHaveResource(resID) then
						return true
					end
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				end
				fi = fi + 1;
			end
		end
		return false
	end
	local function tryTerraformPlace(sp, resID, minRadius, maxRadius, neighborBuf)
		local sx, sy = sp:GetX(), sp:GetY();
		local emptyCands, occupiedCands = {}, {};
		local yy = sy - maxRadius;
		while yy <= sy + maxRadius do
			local xx = sx - maxRadius;
			while xx <= sx + maxRadius do
				local d = Map.PlotDistance(sx, sy, xx, yy);
				if d >= minRadius and d <= maxRadius then
					local plot = Map.GetPlot(xx, yy);
					if plot ~= nil
						and plot:IsWater() == false
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and PlotIsMajorStart(plot) == false
						and inBarrier(xx, yy) == false
						and nearAnyCapital(xx, yy, neighborBuf) == false
						and tooCloseToSame(xx, yy, resID, 2) == false then
						local existingRes = plot:GetResourceType(-1);
						if existingRes == -1 then
							table.insert(emptyCands, plot);
						elseif existingRes ~= resID and allRegionalLuxIDs[existingRes] ~= true then
							table.insert(occupiedCands, plot);
						end
					end
				end
				xx = xx + 1;
			end
			yy = yy + 1;
		end
		if #emptyCands > 1 then
			emptyCands = GetShuffledCopyOfTable(emptyCands);
		end
		local i = 1;
		while i <= #emptyCands do
			if tryTerraformOnPlot(emptyCands[i], resID) then
				emptyCands[i]:SetResourceType(resID, 1);
				return true
			end
			i = i + 1;
		end
		-- As a last resort, terraforming can also legalize an occupied tile
		-- and bounce whatever was there.
		if #occupiedCands > 1 then
			occupiedCands = GetShuffledCopyOfTable(occupiedCands);
		end
		i = 1;
		while i <= #occupiedCands do
			local plot = occupiedCands[i];
			if tryTerraformOnPlot(plot, resID) then
				if IsWeeveeLuxuryID(plot:GetResourceType(-1)) then
					local function banNearCapitalOrBarrier(x, y)
						return inBarrier(x, y) or nearAnyCapital(x, y, neighborBuf);
					end
					TryRelocateLuxury(plot, banNearCapitalOrBarrier, radius + 6);
				end
				if plot:GetResourceType(-1) ~= -1 then
					plot:SetResourceType(-1);
				end
				plot:SetResourceType(resID, 1);
				return true
			end
			i = i + 1;
		end
		return false
	end
	-- Obsidian keeps coming back with BOTH legal lists empty from
	-- resourceLegalTerrains/Features -- its legality isn't governed by
	-- either table, and a mountain-adjacency guess (tried and removed) came
	-- back with the same result: still 4/6, no better than doing nothing.
	-- Rather than keep guessing at the real rule, this forces it directly:
	-- any Plains or Desert tile within radius 8, resource-legality checks
	-- skipped entirely (that's the whole reason this exists -- CanHaveResource
	-- has been uninformative for this specific resource), still respecting
	-- the barrier/capital-ring/spacing rules everything else does.
	local obsidianID = GameInfoTypes["RESOURCE_OBSIDIAN"];
	local function tryForcePlainsDesert(sp, resID, maxRadius, neighborBuf)
		local sx, sy = sp:GetX(), sp:GetY();
		local emptyCands, occupiedCands = {}, {};
		local yy = sy - maxRadius;
		while yy <= sy + maxRadius do
			local xx = sx - maxRadius;
			while xx <= sx + maxRadius do
				local d = Map.PlotDistance(sx, sy, xx, yy);
				if d >= 4 and d <= maxRadius then
					local plot = Map.GetPlot(xx, yy);
					if plot ~= nil
						and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
						and (plot:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS or plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT)
						and PlotIsMajorStart(plot) == false
						and inBarrier(xx, yy) == false
						and nearAnyCapital(xx, yy, neighborBuf) == false
						and tooCloseToSame(xx, yy, resID, 2) == false then
						local existingRes = plot:GetResourceType(-1);
						if existingRes == -1 then
							table.insert(emptyCands, plot);
						elseif existingRes ~= resID and allRegionalLuxIDs[existingRes] ~= true then
							table.insert(occupiedCands, plot);
						end
					end
				end
				xx = xx + 1;
			end
			yy = yy + 1;
		end
		if #emptyCands > 0 then
			if #emptyCands > 1 then
				emptyCands = GetShuffledCopyOfTable(emptyCands);
			end
			emptyCands[1]:SetResourceType(resID, 1);
			return true
		end
		if #occupiedCands < 1 then
			return false
		end
		if #occupiedCands > 1 then
			occupiedCands = GetShuffledCopyOfTable(occupiedCands);
		end
		local bounced = occupiedCands[1];
		if IsWeeveeLuxuryID(bounced:GetResourceType(-1)) then
			local function banNearCapitalOrBarrier(x, y)
				return inBarrier(x, y) or nearAnyCapital(x, y, neighborBuf);
			end
			TryRelocateLuxury(bounced, banNearCapitalOrBarrier, radius + 6);
		end
		if bounced:GetResourceType(-1) ~= -1 then
			bounced:SetResourceType(-1);
		end
		bounced:SetResourceType(resID, 1);
		return true
	end
	local nForced = 0;
	local region_number = 1;
	while region_number <= asp.iNumCivs do
		local playerNum = asp.player_ID_list[region_number];
		local player = nil;
		if playerNum ~= nil then
			player = Players[playerNum];
		end
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil and (DEF_MIRRORED ~= 1 or IsMirrorEastSubject(sp:GetX(), sp:GetY()) == false) then
				local resID = asp.region_luxury_assignment[region_number];
				if resID ~= nil then
					local target = regionalTarget(region_number, resID);
					local have = counts[resID] or 0;
					-- Never touch anything within radius 3 of this capital:
					-- vanilla's own start-tile pass plus EnsureStartLuxuryFloor
					-- already reliably build the classic 3 (regional) + 1
					-- (other) pattern there on their own, before this function
					-- runs. An earlier version of this function also tried to
					-- manage that ring directly (bounce/trim/terraform/retry
					-- to force a "3 near" guarantee) and that was the wrong
					-- call -- it kept introducing new near-capital problems
					-- (overshoot, undershoot, cross-region collateral damage)
					-- in territory that never needed touching. This only
					-- tops up the region-wide total, strictly at radius 4+,
					-- widening the search twice and then trying a legalizing
					-- edit before accepting a genuine shortfall.
					while have < target do
						if tryBounce(sp, resID, 4, radius, 3) then
							have = have + 1;
							counts[resID] = have;
							nForced = nForced + 1;
						else
							break
						end
					end
					-- This tier reaches out to radius 12 -- far enough that a
					-- placement here can otherwise land only 4-5 tiles from a
					-- DIFFERENT capital even while staying outside their
					-- strict radius-3 ring, reading as "sitting right next to
					-- someone else's stuff." Widen the neighbor buffer to 5
					-- for this tier and the terraform tier below (both only
					-- fire after the normal-range tier above has already
					-- failed, so trading a few more candidates for staying
					-- clearly on this region's own side is worth it). The
					-- SHORTFALL diagnostic below confirmed this is worth
					-- doing: some resources (e.g. Silk, legal only on
					-- Forest) have exactly one legalizing option, so a
					-- shortfall for them is pure candidate scarcity within
					-- the search radius, not a missing terraform option --
					-- more room is the only lever left.
					while have < target do
						if tryBounce(sp, resID, radius + 1, radius + 6, 5) then
							have = have + 1;
							counts[resID] = have;
							nForced = nForced + 1;
						else
							break
						end
					end
					while have < target do
						if tryTerraformPlace(sp, resID, 4, radius + 6, 5) then
							have = have + 1;
							counts[resID] = have;
							nForced = nForced + 1;
						else
							break
						end
					end
					-- Obsidian specifically, direct force: any Plains/Desert
					-- tile within radius 8, legality checks skipped.
					if resID == obsidianID then
						while have < target do
							if tryForcePlainsDesert(sp, resID, 8, 5) then
								have = have + 1;
								counts[resID] = have;
								nForced = nForced + 1;
							else
								break
							end
						end
					end
					-- One-time diagnostic for a genuine shortfall that
					-- survived every tier: dump exactly what the ruleset
					-- says legalizes this resource, instead of guessing.
					-- If both lists are non-empty, the bottleneck isn't
					-- "we don't know what this needs" -- it's more likely a
					-- combo (e.g. Hills AND a specific terrain together)
					-- that trying one edit at a time can't reach, or plain
					-- candidate exhaustion within the search radius.
					if have < target then
						local terrainNames, featureNames = {}, {};
						local tl = resourceLegalTerrains(resID);
						local ti = 1;
						while ti <= #tl do
							local info = GameInfo.Terrains[tl[ti]];
							table.insert(terrainNames, info ~= nil and info.Type or tostring(tl[ti]));
							ti = ti + 1;
						end
						local fl = resourceLegalFeatures(resID);
						local fi = 1;
						while fi <= #fl do
							local info = GameInfo.Features[fl[fi]];
							table.insert(featureNames, info ~= nil and info.Type or tostring(fl[fi]));
							fi = fi + 1;
						end
						WeeveeDbgPersist("EnsureRegionalLuxuryTarget SHORTFALL diag Region#" .. region_number .. " LuxID=" .. resID .. " legalTerrains=[" .. table.concat(terrainNames, ",") .. "] legalFeatures=[" .. table.concat(featureNames, ",") .. "]");
					end
					local sx, sy = sp:GetX(), sp:GetY();
					local distToPole = math.min(sy, iH - 1 - sy);
					local rowSkip = RowMireSkip(iW, sy);
					local distToBarrier = -1;
					local col, isSkip;
					for col, isSkip in pairs(rowSkip) do
						if isSkip == true then
							local d = math.abs(sx - col);
							if distToBarrier == -1 or d < distToBarrier then
								distToBarrier = d;
							end
						end
					end
					local resType = "?";
					if GameInfo.Resources[resID] ~= nil and GameInfo.Resources[resID].Type ~= nil then
						resType = GameInfo.Resources[resID].Type;
					end
					-- nearFinal is read-only here -- it never feeds into any
					-- forcing decision, purely confirms in the log that
					-- vanilla's own near-capital shape stayed untouched.
					local nearFinal = countNear(sp, resID, 3);
					WeeveeDbgPersist("EnsureRegionalLuxuryTarget Region#" .. region_number .. " LuxID=" .. resID .. " (" .. resType .. ") target=" .. target .. " final=" .. have .. " nearFinal=" .. nearFinal .. " capital=(" .. sx .. "," .. sy .. ") distToPoleEdge=" .. distToPole .. " distToBarrier=" .. distToBarrier);
				end
			end
		end
		region_number = region_number + 1;
	end
	WeeveeDbgPersist("EnsureRegionalLuxuryTarget forced " .. nForced .. " copies total");
end
------------------------------------------------------------------------------
function StripStartTileLuxuries()
	local n = 0;
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			local sp = player:GetStartingPlot();
			local sx = sp:GetX();
			local sy = sp:GetY();
			local iW, iH = Map.GetGridSize();
			if not (DEF_MIRRORED == 1 and sx >= iW / 2) then
				local res = sp:GetResourceType(-1);
				if IsWeeveeLuxuryID(res) then
					local amt = sp:GetNumResource();
					if amt == nil or amt < 1 then
						amt = 1;
					end
					local cands = {};
					local y = sy - 3;
					while y <= sy + 3 do
						local x = sx - 3;
						while x <= sx + 3 do
							local d = Map.PlotDistance(sx, sy, x, y);
							if d >= 1 and d <= 3 then
								local plot = Map.GetPlot(x, y);
								if plot ~= nil
									and PlotIsMajorStart(plot) == false
									and plot:IsWater() == false
									and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
									and plot:GetResourceType(-1) == -1
									and plot:CanHaveResource(res) then
									table.insert(cands, plot);
								end
							end
							x = x + 1;
						end
						y = y + 1;
					end
					if #cands > 1 then
						cands = GetShuffledCopyOfTable(cands);
					end
					if #cands > 0 then
						cands[1]:SetResourceType(res, amt);
					end
					sp:SetResourceType(-1);
					n = n + 1;
				end
			end
		end
		pi = pi + 1;
	end
	print("Start tile luxuries stripped:", n);
end
------------------------------------------------------------------------------
function ConvertFlatDesertSaltCopper()
	local saltID = GameInfoTypes["RESOURCE_SALT"];
	local copperID = GameInfoTypes["RESOURCE_COPPER"];
	if saltID == nil and copperID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2);
	end
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil
				and plot:GetPlotType() == PlotTypes.PLOT_LAND
				and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
				local res = plot:GetResourceType(-1);
				if res == saltID or res == copperID then
					if Map.Rand(100, "Salt Copper Hill") < 50 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Flat desert salt/copper to hills:", n);
end
------------------------------------------------------------------------------
-- Any Fur sitting on bare Tundra gets Forest added, regardless of how it
-- got there (vanilla placement, EnsureRegionalLuxuryTarget's forcing,
-- EnsureLuxuryQuota padding, ...) or whether a later pass stripped the
-- feature without checking what resource was underneath. Forced
-- unconditionally, same "just plant it" reasoning already applied to Forest
-- elsewhere in this file.
function EnsureFurOnTundraHasForest()
	local furID = GameInfoTypes["RESOURCE_FUR"];
	if furID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2) - 1;
	end
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil
				and plot:GetResourceType(-1) == furID
				and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
				and plot:GetFeatureType() ~= FeatureTypes.FEATURE_FOREST then
				plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
				n = n + 1;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	WeeveeDbg("Fur-on-tundra forced forest: " .. n);
end
------------------------------------------------------------------------------
-- Jade sitting on flat Desert reads oddly next to the rest of Oasis's
-- terrain-appropriate resources -- give it a real chance to become a
-- Desert Hill instead, mirroring WastelandMiningLuxFlatTundraToHill's
-- pattern but scoped to just this one resource, at the user's requested
-- 70% rate. Runs at the very end of the resource pipeline (alongside
-- EnsureFurOnTundraHasForest) so it catches Jade regardless of which pass
-- actually placed it -- vanilla's own placement, EnsureRegionalLuxuryTarget's
-- forcing, or EnsureLuxuryQuota's padding.
function OasisJadeFlatDesertToHill()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "desert" then
		return
	end
	local jadeID = GameInfoTypes["RESOURCE_JADE"];
	if jadeID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local raised = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT
					and plot:GetResourceType(-1) == jadeID then
					if Map.Rand(100, "Oasis Jade flat to hill") < 70 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						raised = raised + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	WeeveeDbg("Oasis Jade flat desert to hill: " .. raised);
end
------------------------------------------------------------------------------
function AddWetlandRiverDesert()
	do return end
	local pct = cfg.riverDesertPct;
	if pct == nil or pct < 1 then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local remaining = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:IsRiver()
					and plot:GetTerrainType() ~= TerrainTypes.TERRAIN_DESERT then
					table.insert(remaining, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local n = #remaining;
	local target = math.floor(n * (pct / 100) + 0.5);
	local placed = 0;
	while placed < target and #remaining > 0 do
		local totalWeight = 0;
		local i = 1;
		while i <= #remaining do
			local neigh = 0;
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(remaining[i]:GetX(), remaining[i]:GetY(), d);
				if adj ~= nil and adj:IsWater() == false and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					neigh = neigh + 1;
				end
				d = d + 1;
			end
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			totalWeight = totalWeight + w;
			i = i + 1;
		end
		if totalWeight < 1 then
			break
		end
		local roll = Map.Rand(totalWeight, "Wetland River Desert");
		i = 1;
		local picked = false;
		while i <= #remaining do
			local neigh = 0;
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(remaining[i]:GetX(), remaining[i]:GetY(), d);
				if adj ~= nil and adj:IsWater() == false and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					neigh = neigh + 1;
				end
				d = d + 1;
			end
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			if roll < w then
				remaining[i]:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
				table.remove(remaining, i);
				placed = placed + 1;
				picked = true;
				break
			end
			roll = roll - w;
			i = i + 1;
		end
		if picked == false then
			remaining[#remaining]:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
			table.remove(remaining, #remaining);
			placed = placed + 1;
		end
	end
	print("Wetland river desert:", placed, "/", n);
end
------------------------------------------------------------------------------
function AddFeatures()
	print("Adding Features (Lua West vs East) ...");

	-- Get Rainfall setting input by user.
	local rain = DEF_RAINFALL;
	if rain == 4 then
		rain = 1 + Map.Rand(3, "Random Rainfall - Lua");
	end
	
	local args = {rainfall = rain}
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "desert" then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 10;
		args.fMarshPercent = 2;
		args.iOasisPercent = 12;
	elseif cfg ~= nil and cfg.kind == "wasteland" then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 52;
		args.fMarshPercent = 1;
		args.iOasisPercent = 0;
	elseif cfg ~= nil and cfg.kind == "wetland" then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 0;
		args.fMarshPercent = 0;
		args.iOasisPercent = 0;
	elseif cfg ~= nil and cfg.kind == "peaks" then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 36;
		args.fMarshPercent = 0;
		args.iOasisPercent = 0;
	elseif cfg ~= nil and cfg.kind == "frosty" then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 28;
		args.fMarshPercent = 0;
		args.iOasisPercent = 0;
	elseif cfg ~= nil and (cfg.kind == "tongue" or cfg.kind == "bramble") then
		args.iJunglePercent = 0;
		args.iJungleFactor = 5;
		args.iForestPercent = 0;
		args.fMarshPercent = 0;
		args.iOasisPercent = 0;
	elseif cfg ~= nil and cfg.kind == "snow" then
		-- Jungle's own latitude gate (FeatureGenerator:AddJunglesAtPlot) only
		-- allows it within lat < 1/iJungleFactor of the map's vertical center,
		-- regardless of iJunglePercent (that knob only affects density inside
		-- the band, not its width). Vanilla's default factor of 5 confines
		-- jungle to roughly the central 20% of map height -- fine on a normal
		-- map where luxury-region weighting can freely pick a non-jungle
		-- civ's own actual mix, but on this map's 3-civs-per-side vertical
		-- split it leaves the outer (non-central) civ(s) with no jungle at
		-- all in reach, so a jungle-locked regional luxury (Cocoa, Spices,
		-- Dye, ...) assigned to one of them can end up impossible to place.
		-- Lowering the factor widens the band (~20% -> ~33%) and the percent
		-- bump keeps density reasonable once inside it, so more of the map's
		-- civs have at least some jungle within their region.
		args.iJunglePercent = 38;
		args.iJungleFactor = 3;
	end
	local featuregen = FeatureGenerator.Create(args);

	AddWastelandWaterLayout();
	featuregen:AddFeatures(true);
	AddDesertJungleBlob();
	AddMireFeatures();
	AddNorthIceArms();
	AddPeaksMassifForests();
	AddPeaksFrontStrayForests();
	AddPeaksInteriorStrayForests();
	AddPeaksMeadows();
	AddPeaksValleyMarsh();
	AddPeaksNorthTundra();
	AddPeaksThawRiverTundra();
	AddPeaksBackCoastForest();
	AddPeaksEconHillFill();
	AddFrostyForests();
	AddFrostySouthJungle();
	AddFrostyIce();
	AddBrambleFeatures();
	ForestMountainsToBareTarget();
	WeeveeLogFlatHillSample();
end
------------------------------------------------------------------------------
-- Debug-only: logs the hill/flat ratio (mountains and water excluded) for
-- each individual econ-zone column, from the actual leftmost column that can
-- ever have land out to a buffer short of the front mountain columns -- one
-- line per column, so it can be checked directly against a manual in-game
-- count instead of going by eye on a pre-summed band. Written to
-- weevee_persist.log (not weevee_dbg.log, which is truncated at the start of
-- every new generation, and not Lua.log/print, which the user has found
-- unreliable) so results from multiple rerolls accumulate in one place.
-- West side only; the mirror always matches it on the east.
function WeeveeLogFlatHillSample()
	local cfg = GetBarrierConfig();
	if cfg == nil or (cfg.kind ~= "snow" and cfg.kind ~= "wetland") then
		return
	end
	local iW, iH = Map.GetGridSize();
	local col1, col2, col3, col4, col5 = GetFrontMountainColumns5West(iW);
	local function sampleColumn(x)
		local hill, flat = 0, 0;
		local y = 0;
		while y < iH do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
				if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
					hill = hill + 1;
				else
					flat = flat + 1;
				end
			end
			y = y + 1;
		end
		local total = hill + flat;
		local pct = 0;
		if total > 0 then
			pct = math.floor(hill * 1000 / total + 0.5) / 10;
		end
		WeeveeDbgPersist("WeeveeFlatHillSample " .. cfg.kind .. " col=" .. x
			.. " hills=" .. hill .. " flat=" .. flat .. " total=" .. total .. " hill%=" .. pct);
	end
	-- Literal 3 leftmost map columns -- the forced-ocean rim this used to
	-- read off of (GeneratePlotsByRegion's x_west/rimW) has since been made
	-- conditional/overwritten later in the pipeline and is no longer a
	-- reliable indicator of where land actually starts.
	local xWest = 0;
	-- Stop a buffer short of col5 (the outermost of the 5 front-mountain
	-- columns) to keep foothill contamination out of the econ-zone read.
	local econEnd = col5 - 4;
	local x = xWest;
	while x <= econEnd do
		sampleColumn(x);
		x = x + 1;
	end
end
------------------------------------------------------------------------------
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function PlotDirNoXWrap(x, y, direction)
	local p = Map.PlotDirection(x, y, direction);
	if p == nil then
		return nil
	end
	if math.abs(p:GetX() - x) > 1 then
		return nil
	end
	return p;
end
------------------------------------------------------------------------------
-- The west/east barrier strip (RowMireSkip's columns, plus Bramble's own
-- separator) is normally dry land as far as the river walk is concerned --
-- ClearRiversNearBarrier only wipes river edges that land inside it well
-- after the fact, which used to leave a river dead-ending right at the
-- barrier's edge on dry land instead of reaching real water. Shared by
-- GetRiverValueAtPlot (steer away from it while a real alternative exists)
-- and DoRiver's own stop condition (treat reaching it as a natural end,
-- same as reaching water, instead of drawing edges inside a zone that's
-- just going to get stripped afterward).
function IsRiverBarrierColumn(x, y)
	if x == nil or y == nil then
		return false
	end
	local iW = Map.GetGridSize();
	if RowMireSkip(iW, y)[x] == true then
		return true
	end
	return TongueIsBarrierPlot(x, y);
end
------------------------------------------------------------------------------
function GetRiverValueAtPlot(plot)
	local x = plot:GetX()
	local y = plot:GetY()
	local numPlots = PlotTypes.NUM_PLOT_TYPES;
	local direction_influence_value = 0;
	if IsRiverBarrierColumn(x, y) then
		direction_influence_value = numPlots * 50;
	end

	local sum = ((numPlots - plot:GetPlotType()) * 20) + direction_influence_value;

	local numDirections = DirectionTypes.NUM_DIRECTION_TYPES;
	for direction = 0, numDirections - 1 do
		local adjacentPlot = PlotDirNoXWrap(plot:GetX(), plot:GetY(), direction);
		if (adjacentPlot ~= nil) then
			sum = sum + (numPlots - adjacentPlot:GetPlotType());
		else
			sum = sum + (numPlots * 10);
		end
	end
	sum = sum + Map.Rand(10, "River Rand");

	return sum;
end
------------------------------------------------------------------------------
function DoRiver(startPlot, thisFlowDirection, originalFlowDirection, riverID)
	-- Customizing to handle problems in top row of the map. Only this aspect has been altered.

	local iW, iH = Map.GetGridSize()
	thisFlowDirection = thisFlowDirection or FlowDirectionTypes.NO_FLOWDIRECTION;
	originalFlowDirection = originalFlowDirection or FlowDirectionTypes.NO_FLOWDIRECTION;

	-- pStartPlot = the plot at whose SE corner the river is starting
	if (riverID == nil) then
		riverID = nextRiverID;
		nextRiverID = nextRiverID + 1;
	end

	local otherRiverID = _rivers[startPlot]
	if (otherRiverID ~= nil and otherRiverID ~= riverID and originalFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
		return; -- Another river already exists here; can't branch off of an existing river!
	end

	local riverPlot;
	
	local bestFlowDirection = FlowDirectionTypes.NO_FLOWDIRECTION;
	if (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTH) then
	
		riverPlot = startPlot;
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if ( adjacentPlot == nil or riverPlot:IsWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater() ) then
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetWOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "W", riverID);
		riverPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
		
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHEAST) then
	
		riverPlot = startPlot;
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHEAST);
		if ( adjacentPlot == nil or riverPlot:IsNWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater() ) then
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNWOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "NW", riverID);
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST) then
	
		riverPlot = PlotDirNoXWrap(startPlot:GetX(), startPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if (riverPlot == nil) then
			return;
		end
		
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		if (adjacentPlot == nil or riverPlot:IsNEOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNEOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "NE", riverID);
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTH) then
	
		riverPlot = PlotDirNoXWrap(startPlot:GetX(), startPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		if (riverPlot == nil) then
			return;
		end
		
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if (adjacentPlot == nil or riverPlot:IsWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			return;
		end
		
		_rivers[riverPlot] = riverID;
		riverPlot:SetWOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "W", riverID);
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST) then

		riverPlot = startPlot;
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHEAST);
		if (adjacentPlot == nil or riverPlot:IsNWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			return;
		end
		
		_rivers[riverPlot] = riverID;
		riverPlot:SetNWOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "NW", riverID);
		-- riverPlot does not change

	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHWEST) then
		
		riverPlot = startPlot;
		local adjacentPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		
		if ( adjacentPlot == nil or riverPlot:IsNEOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNEOfRiver(true, thisFlowDirection);
		RecordRiverEdge(riverPlot, "NE", riverID);
		riverPlot = PlotDirNoXWrap(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_WEST);

	else
		-- River is starting here, set the direction in the next step
		riverPlot = startPlot;		
	end

	if (riverPlot == nil or riverPlot:IsWater() or IsRiverBarrierColumn(riverPlot:GetX(), riverPlot:GetY())) then
		-- The river has flowed off the edge of the map, into the ocean, or up
		-- to the west/east barrier strip -- all three are treated as a
		-- natural end, so the walk never draws edges referencing a plot
		-- inside the barrier for ClearRiversNearBarrier to strip out later.
		return;
	end

	-- Storing X,Y positions as locals to prevent redundant function calls.
	local riverPlotX = riverPlot:GetX();
	local riverPlotY = riverPlot:GetY();
	
	-- Table of methods used to determine the adjacent plot.
	local adjacentPlotFunctions = {
		[FlowDirectionTypes.FLOWDIRECTION_NORTH] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHWEST); 
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_NORTHEAST] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHEAST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_EAST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTH] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_SOUTHWEST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_WEST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_NORTHWEST] = function() 
			return PlotDirNoXWrap(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHWEST);
		end	
	}
	
	if(bestFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then

		-- Attempt to calculate the best flow direction.
		local bestValue = math.huge;
		for flowDirection, getAdjacentPlot in pairs(adjacentPlotFunctions) do
			
			if (GetOppositeFlowDirection(flowDirection) ~= originalFlowDirection) then
				
				if (thisFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION or
					flowDirection == TurnRightFlowDirections[thisFlowDirection] or 
					flowDirection == TurnLeftFlowDirections[thisFlowDirection]) then
				
					local adjacentPlot = getAdjacentPlot();
					
					if (adjacentPlot ~= nil) then
					
						local value = GetRiverValueAtPlot(adjacentPlot);
						if (flowDirection == originalFlowDirection) then
							value = (value * 3) / 4;
						end
						
						if (value < bestValue) then
							bestValue = value;
							bestFlowDirection = flowDirection;
						end

					-- Custom addition for Highlands, to fix river problems in top row of the map. Any other all-land map may need similar special casing.
					elseif adjacentPlot == nil and riverPlotY == iH - 1 then -- Top row of map, needs special handling
						if flowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTH or
						   flowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHWEST or
						   flowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHEAST then
							
							local value = Map.Rand(5, "River Rand");
							if (flowDirection == originalFlowDirection) then
								value = (value * 3) / 4;
							end
							if (value < bestValue) then
								bestValue = value;
								bestFlowDirection = flowDirection;
							end
						end

					-- Custom addition for Highlands, to fix river problems in left column of the map. Any other all-land map may need similar special casing.
					elseif adjacentPlot == nil and riverPlotX == 0 then -- Left column of map, needs special handling
						if flowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTH or
						   flowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTH or
						   flowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHWEST or
						   flowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST then
							
							local value = Map.Rand(5, "River Rand");
							if (flowDirection == originalFlowDirection) then
								value = (value * 3) / 4;
							end
							if (value < bestValue) then
								bestValue = value;
								bestFlowDirection = flowDirection;
							end
						end
					end
				end
			end
		end
		
		-- Try a second pass allowing the river to "flow backwards".
		if(bestFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
		
			local bestValue = math.huge;
			for flowDirection, getAdjacentPlot in pairs(adjacentPlotFunctions) do
			
				if (thisFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION or
					flowDirection == TurnRightFlowDirections[thisFlowDirection] or 
					flowDirection == TurnLeftFlowDirections[thisFlowDirection]) then
				
					local adjacentPlot = getAdjacentPlot();
					
					if (adjacentPlot ~= nil) then
						
						local value = GetRiverValueAtPlot(adjacentPlot);
						if (value < bestValue) then
							bestValue = value;
							bestFlowDirection = flowDirection;
						end
					end	
				end
			end
		end
	end
	
	--Recursively generate river.
	if (bestFlowDirection ~= FlowDirectionTypes.NO_FLOWDIRECTION) then
		if  (originalFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
			originalFlowDirection = bestFlowDirection;
		end
		
		DoRiver(riverPlot, bestFlowDirection, originalFlowDirection, riverID);
	end
end
------------------------------------------------------------------------------
function RecordRiverEdge(plot, kind, riverID)
	if plot == nil or riverID == nil then
		return
	end
	if riverEdgeList[riverID] == nil then
		riverEdgeList[riverID] = {};
	end
	table.insert(riverEdgeList[riverID], {plot:GetX(), plot:GetY(), kind});
end
------------------------------------------------------------------------------
function RiverEdgeStillSet(plot, kind)
	if plot == nil then
		return false
	end
	if kind == "W" then
		return plot:IsWOfRiver();
	end
	if kind == "NW" then
		return plot:IsNWOfRiver();
	end
	if kind == "NE" then
		return plot:IsNEOfRiver();
	end
	return false;
end
------------------------------------------------------------------------------
function ClearRiverEdge(plot, kind)
	if plot == nil then
		return
	end
	if kind == "W" then
		plot:SetWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
	elseif kind == "NW" then
		plot:SetNWOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
	elseif kind == "NE" then
		plot:SetNEOfRiver(false, FlowDirectionTypes.NO_FLOWDIRECTION);
	end
end
------------------------------------------------------------------------------
function RiverEdgesTouchWater(edges)
	local i = 1;
	while i <= #edges do
		local e = edges[i];
		local plot = Map.GetPlot(e[1], e[2]);
		if RiverEdgeStillSet(plot, e[3]) then
			if plot:IsWater() then
				return true
			end
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
				if adj ~= nil and adj:IsWater() then
					return true
				end
				d = d + 1;
			end
		end
		i = i + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function CullShortRivers()
	-- Was Peaks-only, but the thing it does -- delete a river stub that
	-- never reaches any water, instead of leaving it to fizzle out on land
	-- -- isn't Peaks-specific at all: DoRiver's walk (see its own comments)
	-- has no guarantee of reaching water on any climate, it's just more
	-- visible on a small map like Standard-Diagonal's. Generalized to run
	-- everywhere rather than inventing a second copy of the same logic.
	--
	-- Grouping by the riverID DoRiver originally assigned (as this used to)
	-- is wrong once anything runs after AddRivers that can cut a river into
	-- pieces (ClearRiversNearBarrier, OasisStripWestHinterlandRivers, ...):
	-- two now-disconnected fragments that happen to share an old riverID
	-- got judged together, so a short landlocked stub could dodge deletion
	-- just because a different, unrelated fragment sharing that riverID
	-- touched water somewhere else entirely. This instead flood-fills over
	-- the CURRENTLY live edges (the same approach CullWestCoastShortRivers
	-- already uses below, just not restricted to its west-coast columns),
	-- so each judgement is about one actually-connected piece of river.
	local iW, iH = Map.GetGridSize();
	local function edgeKey(x, y, kind)
		return y * iW * 4 + x * 4 + ({W = 1, NW = 2, NE = 3})[kind];
	end
	local function addPlotEdges(plot, list)
		if plot == nil then
			return
		end
		local x, y = plot:GetX(), plot:GetY();
		if plot:IsWOfRiver() then
			table.insert(list, {x, y, "W"});
		end
		if plot:IsNWOfRiver() then
			table.insert(list, {x, y, "NW"});
		end
		if plot:IsNEOfRiver() then
			table.insert(list, {x, y, "NE"});
		end
	end
	local seen = {};
	local nDrop = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local start = {};
				addPlotEdges(plot, start);
				local si = 1;
				while si <= #start do
					local e0 = start[si];
					local k0 = edgeKey(e0[1], e0[2], e0[3]);
					if seen[k0] ~= true then
						local comp = {};
						local qx, qy = {e0[1]}, {e0[2]};
						local qi = 1;
						seen[k0] = true;
						table.insert(comp, e0);
						while qi <= #qx do
							local cx, cy = qx[qi], qy[qi];
							local around = {};
							addPlotEdges(Map.GetPlot(cx, cy), around);
							local d = 0;
							while d < DirectionTypes.NUM_DIRECTION_TYPES do
								local adj = PlotDirNoXWrap(cx, cy, d);
								if adj ~= nil then
									addPlotEdges(adj, around);
								end
								d = d + 1;
							end
							local ai = 1;
							while ai <= #around do
								local ae = around[ai];
								local ak = edgeKey(ae[1], ae[2], ae[3]);
								if seen[ak] ~= true then
									seen[ak] = true;
									table.insert(comp, ae);
									table.insert(qx, ae[1]);
									table.insert(qy, ae[2]);
								end
								ai = ai + 1;
							end
							qi = qi + 1;
						end
						local n = #comp;
						if n > 0 and n <= 5 and RiverEdgesTouchWater(comp) == false then
							local ci = 1;
							while ci <= n do
								ClearRiverEdge(Map.GetPlot(comp[ci][1], comp[ci][2]), comp[ci][3]);
								ci = ci + 1;
							end
							nDrop = nDrop + 1;
						end
					end
					si = si + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Dead-end short rivers dropped:", nDrop);
end
------------------------------------------------------------------------------
function CullWestCoastShortRivers()
	local westMax = 9;
	local nDrop = 0;
	local rid, edges;
	for rid, edges in pairs(riverEdgeList) do
		local n = 0;
		local nWest = 0;
		local i = 1;
		while i <= #edges do
			local e = edges[i];
			if RiverEdgeStillSet(Map.GetPlot(e[1], e[2]), e[3]) then
				n = n + 1;
				if e[1] <= westMax then
					nWest = nWest + 1;
				end
			end
			i = i + 1;
		end
		if n > 0 and n <= 4 and nWest == n then
			i = 1;
			while i <= #edges do
				local e = edges[i];
				ClearRiverEdge(Map.GetPlot(e[1], e[2]), e[3]);
				i = i + 1;
			end
			nDrop = nDrop + 1;
		end
	end
	local iW, iH = Map.GetGridSize();
	local seen = {};
	local function edgeKey(x, y, kind)
		return y * iW * 4 + x * 4 + ({W=1, NW=2, NE=3})[kind];
	end
	local function addPlotEdges(plot, list)
		if plot == nil then
			return
		end
		local x = plot:GetX();
		local y = plot:GetY();
		if plot:IsWOfRiver() then
			table.insert(list, {x, y, "W"});
		end
		if plot:IsNWOfRiver() then
			table.insert(list, {x, y, "NW"});
		end
		if plot:IsNEOfRiver() then
			table.insert(list, {x, y, "NE"});
		end
	end
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= westMax do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local start = {};
				addPlotEdges(plot, start);
				local si = 1;
				while si <= #start do
					local e0 = start[si];
					local k0 = edgeKey(e0[1], e0[2], e0[3]);
					if seen[k0] ~= true and RiverEdgeStillSet(plot, e0[3]) then
						local comp = {};
						local qx = {e0[1]};
						local qy = {e0[2]};
						local qk = {e0[3]};
						local qi = 1;
						seen[k0] = true;
						table.insert(comp, e0);
						while qi <= #qx do
							local cx = qx[qi];
							local cy = qy[qi];
							local around = {};
							addPlotEdges(Map.GetPlot(cx, cy), around);
							local d = 0;
							while d < DirectionTypes.NUM_DIRECTION_TYPES do
								local adj = PlotDirNoXWrap(cx, cy, d);
								if adj ~= nil then
									addPlotEdges(adj, around);
								end
								d = d + 1;
							end
							local ai = 1;
							while ai <= #around do
								local ae = around[ai];
								local ak = edgeKey(ae[1], ae[2], ae[3]);
								if seen[ak] ~= true and RiverEdgeStillSet(Map.GetPlot(ae[1], ae[2]), ae[3]) then
									seen[ak] = true;
									table.insert(comp, ae);
									table.insert(qx, ae[1]);
									table.insert(qy, ae[2]);
									table.insert(qk, ae[3]);
								end
								ai = ai + 1;
							end
							qi = qi + 1;
						end
						local n = #comp;
						local allWest = true;
						local ci = 1;
						while ci <= n do
							if comp[ci][1] > westMax then
								allWest = false;
								break
							end
							ci = ci + 1;
						end
						if n > 0 and n <= 4 and allWest then
							ci = 1;
							while ci <= n do
								ClearRiverEdge(Map.GetPlot(comp[ci][1], comp[ci][2]), comp[ci][3]);
								ci = ci + 1;
							end
							nDrop = nDrop + 1;
						end
					end
					si = si + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("West coast short rivers dropped:", nDrop);
end
------------------------------------------------------------------------------
function AddRivers()

	-- Customization for Skirmish, to keep river starts away from buffer zone in middle columns of map, and set river "original flow direction".
	local iW, iH = Map.GetGridSize()
	print("Skirmish - Adding Rivers");
	riverEdgeList = {};
	local SplitOps = Map.GetCustomOption(OPT_CENTER_SPLIT)
	local snowRiverSkipActive = (IsOldSnow() or IsSnowBarrier());
	local cfgRiversSkip = GetBarrierConfig();
	local peaksRiversSkip = (cfgRiversSkip ~= nil and cfgRiversSkip.kind == "peaks");
	local function snowRiverSkip(x, y)
		if snowRiverSkipActive == false then
			return false
		end
		if peaksRiversSkip == false then
			local snowCols = GetSnowWrapColumns(iW, y);
			local si = 1;
			while si <= #snowCols do
				if snowCols[si] == x then
					return true
				end
				si = si + 1;
			end
		end
		local tundraCols = GetSnowWrapTundraColumns(iW, y);
		local si = 1;
		while si <= #tundraCols do
			if tundraCols[si] == x then
				return true
			end
			si = si + 1;
		end
		return false
	end
	local passConditions = {
		function(plot)
			return plot:IsHills() or plot:IsMountain();
		end,
		
		function(plot)
			return (not plot:IsCoastalLand()) and (Map.Rand(8, "HBTMapGenerator AddRivers") == 0);
		end,
		
		function(plot)
			local area = plot:Area();
			local plotsPerRiverEdge = GameDefines["PLOTS_PER_RIVER_EDGE"];
			return (plot:IsHills() or plot:IsMountain()) and (area:GetNumRiverEdges() <	((area:GetNumTiles() / plotsPerRiverEdge) + 1));
		end,
		
		function(plot)
			local area = plot:Area();
			local plotsPerRiverEdge = GameDefines["PLOTS_PER_RIVER_EDGE"];
			return (area:GetNumRiverEdges() < (area:GetNumTiles() / plotsPerRiverEdge) + 1);
		end,

		function(plot)
			local bi = plot:GetY() * iW + plot:GetX() + 1;
			return mireBand[bi] == 3 and (not plot:IsCoastalLand()) and (Map.Rand(5, "Mire Fen River") == 0);
		end
	}
	local cfgRivers = GetBarrierConfig();
	local peaksRivers = (cfgRivers ~= nil and cfgRivers.kind == "peaks");
	for iPass, passCondition in ipairs(passConditions) do
		local usePass = true;
		if peaksRivers then
			if iPass == 2 or iPass == 4 or iPass == 5 then
				usePass = false;
			end
		end
		if usePass then
		local riverSourceRange;
		local seaWaterRange;
		if (iPass <= 2) then
			riverSourceRange = GameDefines["RIVER_SOURCE_MIN_RIVER_RANGE"];
			seaWaterRange = GameDefines["RIVER_SOURCE_MIN_SEAWATER_RANGE"];
		else
			riverSourceRange = (GameDefines["RIVER_SOURCE_MIN_RIVER_RANGE"] / 2);
			seaWaterRange = (GameDefines["RIVER_SOURCE_MIN_SEAWATER_RANGE"] / 2);
		end
		if peaksRivers and iPass == 1 then
			riverSourceRange = 2;
		end
		for i, plot in Plots() do
			local current_x = plot:GetX()
			local current_y = plot:GetY()
			if current_y < 2 or current_y >= iH - 1 then
				-- Plot too close to north/south edge, ignore it.
			elseif DEF_MIRRORED == 1 and current_x >= iW / 2 then
				-- East is filled by the 180° copy; don't generate a second set.
			elseif IsSnowNoWrap() and (current_x < 2 or current_x >= iW - 2) then
				-- Plot too close to east/west 2-col ocean rims, ignore it.
			elseif IsSnowWrapX() == false and (current_x < 1 or current_x >= iW - 2) then
				-- Plot too close to east/west ocean rims, ignore it.
			elseif IsSnowWrapX() and (current_x < 4 or current_x >= iW - 4) then
				-- Plot in wrap-front buffer, ignore it.
			elseif OasisIsWestHinterlandX(current_x, iW) then
				-- Oasis tack-on desert: no river sources.
			elseif snowRiverSkip(current_x, current_y) then
				-- Plot in buffer zone, ignore it.
			elseif TongueIsBarrierPlot(current_x, current_y) then
				-- Plot in tongue barrier, ignore it.
			elseif (not plot:IsWater()) then
				local peaksOk = true;
				if peaksRivers then
					local di = current_y * iW + current_x + 1;
					local dPeak = peakDist[di];
					if dPeak == nil or dPeak < 1 or dPeak > 3 then
						peaksOk = false;
					end
				end
				if peaksOk and passCondition(plot) then
					if (not Map.FindWater(plot, riverSourceRange, true)) then
						if (not Map.FindWater(plot, seaWaterRange, false)) then
							local inlandCorner = plot:GetInlandCorner();
							if(inlandCorner) then
								local start_x = inlandCorner:GetX()
								local start_y = inlandCorner:GetY()
								local orig_direction;
								local cfgR = GetBarrierConfig();
								if cfgR ~= nil and cfgR.kind == "peaks" then
									local pi = start_y * iW + start_x + 1;
									local px = peakNX[pi];
									local py = peakNY[pi];
									if px == nil then
										px = start_x;
										py = start_y;
									end
									local dx = start_x - px;
									local dy = start_y - py;
									if dx < 0 then
										dx = 0 - dx;
									end
									if dy < 0 then
										dy = 0 - dy;
									end
									local east = start_x >= px;
									local north = start_y >= py;
									if dx >= dy then
										if east then
											if north then
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST;
											else
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST;
											end
										else
											if north then
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST;
											else
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST;
											end
										end
									else
										if north then
											if east then
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST;
											else
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST;
											end
										else
											if east then
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST;
											else
												orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST;
											end
										end
									end
								elseif IsSnowBarrier() then
									local lakeX = iW / 4;
									if start_x >= iW / 2 then
										lakeX = iW * 0.75;
									end
									if start_y < iH / 2 then
										if start_x < lakeX then
											orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST;
										else
											orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST;
										end
									else
										if start_x < lakeX then
											orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST;
										else
											orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST;
										end
									end
								elseif start_y < iH / 2 then -- South half of map
									if start_x < iW / 2 then -- West half of map
										orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST;
									else -- East half
										orig_direction = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST;
									end
								else -- North half of map
									if start_x < iW / 2 then -- West half of map
										orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST;
									else -- NE corner
										orig_direction = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST;
									end
								end
								DoRiver(inlandCorner, nil, orig_direction, nil);
							end
						end
					end
				end			
			end
		end
		end
	end
	OasisStripWestHinterlandRivers();
end
------------------------------------------------------------------------------------------------------------------------------------------------------------
function AssignStartingPlots:GenerateRegions(args)
	print("Map Generation - Dividing the map in to Regions");
	-- This is a customized version for West vs East.
	-- This version is tailored for handling two-teams play.
	local args = args or {};
	local iW, iH = Map.GetGridSize();
	local res = DEF_RESOURCES;
	if res == 9 then
		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
	end

	local setback = DEF_FRONTLINE-1;

	local setforward = DEF_BACK-1;

	local setrange = setforward + setback;

	print("Moveback: ", setback);

	local setmiddle = DEF_TOPBOTTOM-1;

	self.resource_setting = res; -- Each map script has to pass in parameter for Resource setting chosen by user.
	self.method = 3; -- Flag the map as using a Rectangular division method.

	-- Determine number of civilizations and city states present in this game.
	self.iNumCivs, self.iNumCityStates, self.player_ID_list, self.bTeamGame, self.teams_with_major_civs, self.number_civs_per_team = GetPlayerAndTeamInfo()
	self.iNumCityStatesUnassigned = self.iNumCityStates;
	print("-"); print("Civs:", self.iNumCivs); print("City States:", self.iNumCityStates);

	-- Determine number of teams (of Major Civs only, not City States) present in this game.
	iNumTeams = table.maxn(self.teams_with_major_civs);				-- GLOBAL
	print("-"); print("Teams:", iNumTeams);

	-- Fetch team setting.
	local team_setting = DEF_TEAM

	-- If two teams are present, use team-oriented handling of start points, one team west, one east.
	if iNumTeams == 2 and team_setting == 1 then
		print("-"); print("Number of Teams present is two! Using custom team start placement for West vs East."); print("-");
		
		-- ToDo: Correctly identify team IDs and how many Civs are on each team.
		-- Also need to shuffle the teams so its random who starts on which half.
		local shuffled_team_list = GetShuffledCopyOfTable(self.teams_with_major_civs)
		teamWestID = self.teams_with_major_civs[1];							-- GLOBAL
		teamEastID = self.teams_with_major_civs[2]; 						-- GLOBAL
		iNumCivsInWest = self.number_civs_per_team[teamWestID];		-- GLOBAL
		iNumCivsInEast = self.number_civs_per_team[teamEastID];		-- GLOBAL

		-- Process the team in the west.
		self.inhabited_WestX = 0 + setforward;
		self.inhabited_SouthY = 0 + setmiddle;
		self.inhabited_Width = (math.floor(iW / 2)) - setrange;
		self.inhabited_Height = iH - 2 * setmiddle;
		if IsSnowBarrier() then
			local wrapN, centerN = ResolveSnowWrapWidths();
			local wrapHalf = wrapN / 2;
			local centerHalf = centerN / 2;
			local mid = math.floor(iW / 2);
			local backPad = wrapHalf - 1;
			if backPad < 0 then
				backPad = 0;
			end
			self.inhabited_WestX = setforward + backPad;
			if IsTiltedMirrorAxis() then
				centerHalf = 0;
			end
			self.inhabited_Width = (mid - centerHalf) - setback - 1 - self.inhabited_WestX + 1;
			if IsTiltedMirrorAxis() and IsBramble() == false then
				local keep = math.floor(self.inhabited_Height * 0.62);
				if keep < 8 then
					keep = 8;
				end
				if keep < self.inhabited_Height then
					self.inhabited_Height = keep;
				end
			end
		end
		if IsOasisClimate() then
			local band = OasisWestDesertColumns();
			if self.inhabited_WestX < band then
				local shift = band - self.inhabited_WestX;
				self.inhabited_WestX = band;
				self.inhabited_Width = self.inhabited_Width - shift;
			end
			if self.inhabited_Width < 2 then
				self.inhabited_Width = 2;
			end
		end
		-- Obtain "Start Placement Fertility" inside the rectangle.
		-- Data returned is: fertility table, sum of all fertility, plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityInRectangle(self.inhabited_WestX, 
		                                         self.inhabited_SouthY, self.inhabited_Width, self.inhabited_Height)
		-- Assemble the Rectangle data table:
		local rect_table = {self.inhabited_WestX, self.inhabited_SouthY, self.inhabited_Width, 
		                    self.inhabited_Height, -1, fertCount, plotCount}; -- AreaID -1 means ignore area IDs.
		-- Divide the rectangle.
		self:DivideIntoRegions(iNumCivsInWest, fert_table, rect_table)

		-- Process the team in the east.
		self.inhabited_WestX = (math.floor(iW / 2)) + setback;
		self.inhabited_SouthY = 0 + setmiddle;
		self.inhabited_Width = math.floor(iW / 2) - setrange;
		self.inhabited_Height = iH - 2 * setmiddle;
		if IsSnowBarrier() then
			local wrapN, centerN = ResolveSnowWrapWidths();
			local wrapHalf = wrapN / 2;
			local centerHalf = centerN / 2;
			local mid = math.floor(iW / 2);
			if IsTiltedMirrorAxis() then
				centerHalf = 0;
			end
			self.inhabited_WestX = (mid + centerHalf) + setback;
			local lastEast = iW - setforward - 1;
			if wrapHalf > 1 then
				lastEast = iW - setforward - wrapHalf;
			end
			self.inhabited_Width = lastEast - self.inhabited_WestX + 1;
			if IsTiltedMirrorAxis() and IsBramble() == false then
				local keep = math.floor(self.inhabited_Height * 0.62);
				if keep < 8 then
					keep = 8;
				end
				if keep < self.inhabited_Height then
					self.inhabited_SouthY = self.inhabited_SouthY + (self.inhabited_Height - keep);
					self.inhabited_Height = keep;
				end
			end
		end
		if IsOasisClimate() then
			local band = OasisWestDesertColumns();
			local last = self.inhabited_WestX + self.inhabited_Width - 1;
			local maxEast = iW - 1 - band;
			if last > maxEast then
				self.inhabited_Width = maxEast - self.inhabited_WestX + 1;
			end
			if self.inhabited_Width < 2 then
				self.inhabited_Width = 2;
			end
		end
		-- Obtain "Start Placement Fertility" inside the rectangle.
		-- Data returned is: fertility table, sum of all fertility, plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityInRectangle(self.inhabited_WestX, 
		                                         self.inhabited_SouthY, self.inhabited_Width, self.inhabited_Height)
		-- Assemble the Rectangle data table:
		local rect_table = {self.inhabited_WestX, self.inhabited_SouthY, self.inhabited_Width, 
		                    self.inhabited_Height, -1, fertCount, plotCount}; -- AreaID -1 means ignore area IDs.
		-- Divide the rectangle.
		self:DivideIntoRegions(iNumCivsInEast, fert_table, rect_table)
		-- The regions have been defined.

	-- If number of teams is any number other than two, use standard One Landmass division.
	else	
		print("-"); print("Dividing the map at random."); print("-");
		self.method = 2;	
		local best_areas = {};
		local globalFertilityOfLands = {};

		-- Obtain info on all landmasses for comparision purposes.
		local iGlobalFertilityOfLands = 0;
		local iNumLandPlots = 0;
		local iNumLandAreas = 0;
		local land_area_IDs = {};
		local land_area_plots = {};
		local land_area_fert = {};
		-- Cycle through all plots in the world, checking their Start Placement Fertility and AreaID.
		for x = 0, iW - 1 do
			for y = 0, iH - 1 do
				local i = y * iW + x + 1;
				local plot = Map.GetPlot(x, y);
				if not plot:IsWater() then -- Land plot, process it.
					iNumLandPlots = iNumLandPlots + 1;
					local iArea = plot:GetArea();
					local plotFertility = self:MeasureStartPlacementFertilityOfPlot(x, y, true); -- Check for coastal land is enabled.
					iGlobalFertilityOfLands = iGlobalFertilityOfLands + plotFertility;
					--
					if TestMembership(land_area_IDs, iArea) == false then -- This plot is the first detected in its AreaID.
						iNumLandAreas = iNumLandAreas + 1;
						table.insert(land_area_IDs, iArea);
						land_area_plots[iArea] = 1;
						land_area_fert[iArea] = plotFertility;
					else -- This AreaID already known.
						land_area_plots[iArea] = land_area_plots[iArea] + 1;
						land_area_fert[iArea] = land_area_fert[iArea] + plotFertility;
					end
				end
			end
		end
		
		-- Sort areas, achieving a list of AreaIDs with best areas first.
		--
		-- Fertility data in land_area_fert is stored with areaID index keys.
		-- Need to generate a version of this table with indices of 1 to n, where n is number of land areas.
		local interim_table = {};
		for loop_index, data_entry in pairs(land_area_fert) do
			table.insert(interim_table, data_entry);
		end
		-- Sort the fertility values stored in the interim table. Sort order in Lua is lowest to highest.
		table.sort(interim_table);
		-- If less players than landmasses, we will ignore the extra landmasses.
		local iNumRelevantLandAreas = math.min(iNumLandAreas, self.iNumCivs);
		-- Now re-match the AreaID numbers with their corresponding fertility values
		-- by comparing the original fertility table with the sorted interim table.
		-- During this comparison, best_areas will be constructed from sorted AreaIDs, richest stored first.
		local best_areas = {};
		-- Currently, the best yields are at the end of the interim table. We need to step backward from there.
		local end_of_interim_table = table.maxn(interim_table);
		-- We may not need all entries in the table. Process only iNumRelevantLandAreas worth of table entries.
		for areaTestLoop = end_of_interim_table, (end_of_interim_table - iNumRelevantLandAreas + 1), -1 do
			for loop_index, AreaID in ipairs(land_area_IDs) do
				if interim_table[areaTestLoop] == land_area_fert[land_area_IDs[loop_index]] then
					table.insert(best_areas, AreaID);
					table.remove(land_area_IDs, landLoop);
					break
				end
			end
		end

		-- Assign continents to receive start plots. Record number of civs assigned to each landmass.
		local inhabitedAreaIDs = {};
		local numberOfCivsPerArea = table.fill(0, iNumRelevantLandAreas); -- Indexed in synch with best_areas. Use same index to match values from each table.
		for civToAssign = 1, self.iNumCivs do
			local bestRemainingArea;
			local bestRemainingFertility = 0;
			local bestAreaTableIndex;
			-- Loop through areas, find the one with the best remaining fertility (civs added 
			-- to a landmass reduces its fertility rating for subsequent civs).
			for area_loop, AreaID in ipairs(best_areas) do
				local thisLandmassCurrentFertility = land_area_fert[AreaID] / (1 + numberOfCivsPerArea[area_loop]);
				if thisLandmassCurrentFertility > bestRemainingFertility then
					bestRemainingArea = AreaID;
					bestRemainingFertility = thisLandmassCurrentFertility;
					bestAreaTableIndex = area_loop;
				end
			end
			-- Record results for this pass. (A landmass has been assigned to receive one more start point than it previously had).
			numberOfCivsPerArea[bestAreaTableIndex] = numberOfCivsPerArea[bestAreaTableIndex] + 1;
			if TestMembership(inhabitedAreaIDs, bestRemainingArea) == false then
				table.insert(inhabitedAreaIDs, bestRemainingArea);
			end
		end
				
		-- Loop through the list of inhabited landmasses, dividing each landmass in to regions.
		-- Note that it is OK to divide a continent with one civ on it: this will assign the whole
		-- of the landmass to a single region, and is the easiest method of recording such a region.
		local iNumInhabitedLandmasses = table.maxn(inhabitedAreaIDs);
		for loop, currentLandmassID in ipairs(inhabitedAreaIDs) do
			-- Obtain the boundaries of and data for this landmass.
			local landmass_data = ObtainLandmassBoundaries(currentLandmassID);
			local iWestX = landmass_data[1];
			local iSouthY = landmass_data[2];
			local iEastX = landmass_data[3];
			local iNorthY = landmass_data[4];
			local iWidth = landmass_data[5];
			local iHeight = landmass_data[6];
			local wrapsX = landmass_data[7];
			local wrapsY = landmass_data[8];
			-- Obtain "Start Placement Fertility" of the current landmass. (Necessary to do this
			-- again because the fert_table can't be built prior to finding boundaries, and we had
			-- to ID the proper landmasses via fertility to be able to figure out their boundaries.
			local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityOfLandmass(currentLandmassID, 
		  	                                         iWestX, iEastX, iSouthY, iNorthY, wrapsX, wrapsY);
			-- Assemble the rectangle data for this landmass.
			local rect_table = {iWestX, iSouthY, iWidth, iHeight, currentLandmassID, fertCount, plotCount};
			-- Divide this landmass in to number of regions equal to civs assigned here.
			iNumCivsOnThisLandmass = numberOfCivsPerArea[loop];
			if iNumCivsOnThisLandmass > 0 and iNumCivsOnThisLandmass <= 22 then -- valid number of civs.
				self:DivideIntoRegions(iNumCivsOnThisLandmass, fert_table, rect_table)
			else
				print("Invalid number of civs assigned to a landmass: ", iNumCivsOnThisLandmass);
			end
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:BalanceAndAssign()
	-- This function determines what level of Bonus Resource support a location
	-- may need, identifies compatibility with civ-specific biases, and places starts.

	-- Normalize each start plot location.
	local iNumStarts = table.maxn(self.startingPlots);
	for region_number = 1, iNumStarts do
		print("Normalize Region: ", region_number);
		self:NormalizeStartLocation(region_number)
	end

	-- Assign Civs to start plots.
	local team_setting = DEF_TEAM
	if iNumTeams == 2 and team_setting == 1 then
		-- Two teams, place one in the west half, other in east -- even if team membership totals are uneven.
		print("-"); print("This is a team game with two teams! Place one team in West, other in East."); print("-");
		local playerList, westList, eastList = {}, {}, {};
		for loop = 1, self.iNumCivs do
			local player_ID = self.player_ID_list[loop];
			table.insert(playerList, player_ID);
			local player = Players[player_ID];
			local team_ID = player:GetTeam()
			if team_ID == teamWestID then
				print("Player #", player_ID, "belongs to Team #", team_ID, "and will be placed in the North.");
				table.insert(westList, player_ID);
			elseif team_ID == teamEastID then
				print("Player #", player_ID, "belongs to Team #", team_ID, "and will be placed in the South.");
				table.insert(eastList, player_ID);
			else
				print("* ERROR * - Player #", player_ID, "belongs to Team #", team_ID, "which is neither West nor East!");
			end
		end
		
		-- Debug
		if table.maxn(westList) ~= iNumCivsInWest then
			print("-"); print("*** ERROR! *** . . . Mismatch between number of Civs on West team and number of civs assigned to west locations.");
		end
		if table.maxn(eastList) ~= iNumCivsInEast then
			print("-"); print("*** ERROR! *** . . . Mismatch between number of Civs on East team and number of civs assigned to east locations.");
		end
		
		local westListShuffled = GetShuffledCopyOfTable(westList)
		local eastListShuffled = GetShuffledCopyOfTable(eastList)
		for region_number, player_ID in ipairs(westListShuffled) do
			local x = self.startingPlots[region_number][1];
			local y = self.startingPlots[region_number][2];
			local start_plot = Map.GetPlot(x, y)
			local player = Players[player_ID]
			player:SetStartingPlot(start_plot)
		end
		for loop, player_ID in ipairs(eastListShuffled) do
			local x = self.startingPlots[loop + iNumCivsInWest][1];
			local y = self.startingPlots[loop + iNumCivsInWest][2];
			local start_plot = Map.GetPlot(x, y)
			local player = Players[player_ID]
			player:SetStartingPlot(start_plot)
		end
	else
		print("-"); print("This game does not have specific start zone assignments."); print("-");
		local playerList = {};
		for loop = 1, self.iNumCivs do
			local player_ID = self.player_ID_list[loop];
			table.insert(playerList, player_ID);
		end
		local playerListShuffled = GetShuffledCopyOfTable(playerList)
		for region_number, player_ID in ipairs(playerListShuffled) do
			local x = self.startingPlots[region_number][1];
			local y = self.startingPlots[region_number][2];
			local start_plot = Map.GetPlot(x, y)
			local player = Players[player_ID]
			player:SetStartingPlot(start_plot)
		end
		-- If this is a team game (any team has more than one Civ in it) then make 
		-- sure team members start near each other if possible. (This may scramble 
		-- Civ biases in some cases, but there is no cure).
		if self.bTeamGame == true and team_setting ~= 2 then
			print("However, this IS a team game, so we will try to group team members together."); print("-");
			self:NormalizeTeamLocations()
		end
	end
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function AssignStartingPlots:CanPlaceCityStateAt(x, y, area_ID, force_it, ignore_collisions)
	-- Overriding default city state placement to prevent city states from being placed too close to map edges.
	
	--disable city states
	if 1<2 then
		return false
	end

	local iW, iH = Map.GetGridSize();
	local plot = Map.GetPlot(x, y)
	local area = plot:GetArea()
	
	-- Adding this check for West vs East.
	if x < 1 or x >= iW - 1 or y < 1 or y >= iH - 1 then
		return false
	end
	--
	
	if area ~= area_ID and area_ID ~= -1 then
		return false
	end
	local plotType = plot:GetPlotType()
	if plotType == PlotTypes.PLOT_OCEAN or plotType == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	local terrainType = plot:GetTerrainType()
	if terrainType == TerrainTypes.TERRAIN_SNOW then
		return false
	end
	local plotIndex = y * iW + x + 1;
	if self.cityStateData[plotIndex] > 0 and force_it == false then
		return false
	end
	local plotIndex = y * iW + x + 1;
	if self.playerCollisionData[plotIndex] == true and ignore_collisions == false then
		--print("-"); print("City State candidate plot rejected: collided with already-placed civ or City State at", x, y);
		return false
	end
	return true
end
------------------------------------------------------------------------------------------------------------------------------------------------------------
function SetDivide()

	local SplitOps = Map.GetCustomOption(OPT_CENTER_SPLIT);
	local iW, iH = Map.GetGridSize();

	if false then -- Landbridges
		-- check landbridges have no lakes or moutains

		--check bottom land bridge
		for y = 0, 2 do
			for x = math.floor(iW / 2) - 4, math.floor(iW / 2) + 3 do
				local plot = Map.GetPlot(x, y)
				
				--check for mountain or lake
				if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				elseif plot:IsLake() then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
			end
		end

		--check the top landbridge
		for y = (iH-3), (iH-1) do
			for x = math.floor(iW / 2) - 4, math.floor(iW / 2) + 3 do
				local plot = Map.GetPlot(x, y)
				
				--check for mountain or lake
				if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				elseif plot:IsLake() then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
			end
		end

		--check the middle landbridge
		for y = math.floor(iH / 2) - 1, math.floor(iH / 2) + 1 do
			for x = math.floor(iW / 2) - 4, math.floor(iW / 2) + 3 do
				local plot = Map.GetPlot(x, y)
				
				--check for mountain or lake
				if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				elseif plot:IsLake() then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
			end
		end
	elseif false then -- Marsh
		--Marsh
		
		-- Add strip of marsh to middle of map
		for y = 0, iH - 1 do
			for x = math.floor(iW / 2) - 2, math.floor(iW / 2) + 1 do
				local plot = Map.GetPlot(x, y)
				plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
				plot:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1);
			end
		end
	elseif IsOldSnow() then
		local tundraCols = GetSnowWrapTundraColumns(iW);
		local snowCols = GetSnowWrapColumns(iW);
		for y = 0, iH - 1 do
			for _, x in ipairs(tundraCols) do
				local plot = Map.GetPlot(x, y)
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
			end
			for _, x in ipairs(snowCols) do
				local plot = Map.GetPlot(x, y)
				if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				elseif plot:IsLake() then
					plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				plot:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
			end
		end
	elseif IsSnowBarrier() then
		local cfg = GetBarrierConfig();
		local barrierTerrain = BarrierTerrainType(cfg);
		local transTerrain = BarrierTransitionType(cfg);
		local mirrored = (DEF_MIRRORED == 1);
		local hillTop = cfg.mountainPct + cfg.hillPct;
		for y = 0, iH - 1 do
			local tundraCols = GetSnowWrapTundraColumns(iW, y);
			local snowCols = GetSnowWrapColumns(iW, y);
			for _, x in ipairs(tundraCols) do
				if MirrorOwnsPlot(x, y, mirrored, iW) then
					local plot = Map.GetPlot(x, y)
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
					plot:SetTerrainType(transTerrain, false, false);
				end
			end
			for _, x in ipairs(snowCols) do
				if MirrorOwnsPlot(x, y, mirrored, iW) then
					local plot = Map.GetPlot(x, y)
					if plot:IsWater() then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
					end
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
					plot:SetTerrainType(barrierTerrain, false, false);
					if cfg.kind == "snow" then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
					elseif cfg.iceLakePermille > 0 and Map.Rand(1000, "Barrier Ice Lake") < cfg.iceLakePermille then
						plot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
						plot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
						plot:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
					else
						local pt = Map.Rand(100, "Barrier Plot Type");
						if pt < cfg.mountainPct then
							plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
						elseif pt < hillTop then
							plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						else
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
						end
						if cfg.kind == "wetland" then
							-- The econ zones' own tundra bands sit at opposite
							-- ends of the map (mirroring turns west's tundra
							-- edge into east's tundra edge on the far side),
							-- so bleed tundra into the barrier from BOTH the
							-- y=iH-1 and y=0 ends, fading through a plains
							-- transition into the barrier's normal grass/
							-- marsh-eligible vertical center. Only the y=iH-1
							-- end is coded explicitly -- since this whole loop
							-- only ever writes plots MirrorOwnsPlot lets it
							-- write, the standard end-of-generation mirror
							-- copy reproduces the fade at the y=0 end from it.
							local yNorm = 0;
							if iH > 1 then
								yNorm = y / (iH - 1);
							end
							local roll = Map.Rand(100, "Wetland Barrier Terrain");
							if yNorm >= 0.78 then
								local t = (yNorm - 0.78) / 0.22;
								if roll < 40 + t * 55 then
									plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
								else
									plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								end
							elseif yNorm >= 0.5 then
								local t = (yNorm - 0.5) / 0.28;
								if roll < 25 + t * 45 then
									plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								else
									plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
								end
							else
								if roll < 20 then
									plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								else
									plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
								end
							end
						end
					end
				end
			end
		end
	end
	PaintStandardSnowRelief();
	CapBarrierMountains();
end

------------------------------------------------------------------------------
function PaintStandardSnowRelief()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "snow" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local evenN = {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	local oddN = {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
	local land = {};
	local y = 0;
	while y < iH do
		local snowCols = GetSnowWrapColumns(iW, y);
		local tundra = {};
		local tc = GetSnowWrapTundraColumns(iW, y);
		local ti = 1;
		while ti <= #tc do
			tundra[tc[ti]] = true;
			ti = ti + 1;
		end
		local ci = 1;
		while ci <= #snowCols do
			local x = snowCols[ci];
			if tundra[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					table.insert(land, plot);
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	if #land < 1 then
		return
	end
	local function isTundraColAt(x, y)
		local tc = GetSnowWrapTundraColumns(iW, y);
		local i = 1;
		while i <= #tc do
			if tc[i] == x then
				return true
			end
			i = i + 1;
		end
		return false
	end
	local nPeak = 2 + Map.Rand(2, "Snow Peak Count");
	local gap = math.floor(#land / (nPeak + 1));
	if gap < 2 then
		gap = 2;
	end
	local nMtn = 0;
	local nHill = 0;
	local pi = 1;
	while pi <= nPeak do
		local idx = gap * pi;
		if idx > #land then
			idx = #land;
		end
		local jitter = 0;
		if gap > 2 then
			jitter = Map.Rand(3, "Snow Peak Jitter") - 1;
		end
		idx = idx + jitter;
		if idx < 1 then
			idx = 1;
		end
		if idx > #land then
			idx = #land;
		end
		local seed = land[idx];
		seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
		nMtn = nMtn + 1;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(seed:GetX(), seed:GetY(), d);
			if adj ~= nil and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
				if isTundraColAt(adj:GetX(), adj:GetY()) ~= true then
					adj:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
					nHill = nHill + 1;
				end
			end
			d = d + 1;
		end
		d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(seed:GetX(), seed:GetY(), d);
			if adj ~= nil then
				local d2 = 0;
				while d2 < DirectionTypes.NUM_DIRECTION_TYPES do
					local ring = PlotDirNoXWrap(adj:GetX(), adj:GetY(), d2);
					if ring ~= nil and ring:IsWater() == false and ring:GetPlotType() == PlotTypes.PLOT_LAND then
		if isTundraColAt(adj:GetX(), adj:GetY()) ~= true and Map.Rand(100, "Snow Foothill") < 28 then
							ring:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
							nHill = nHill + 1;
						end
					end
					d2 = d2 + 1;
				end
			end
			d = d + 1;
		end
		pi = pi + 1;
	end
	local nRidge = 1 + Map.Rand(2, "Snow Ridge Count");
	local ri = 1;
	while ri <= nRidge do
		local seed = land[Map.Rand(#land, "Snow Ridge Seed") + 1];
		if seed:GetPlotType() == PlotTypes.PLOT_LAND then
			seed:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			nHill = nHill + 1;
			local len = 2 + Map.Rand(2, "Snow Ridge Len");
			local cx = seed:GetX();
			local cy = seed:GetY();
			local step = 1;
			while step < len do
				local dirs = evenN;
				if cy % 2 ~= 0 then
					dirs = oddN;
				end
				local picks = {};
				local di = 1;
				while di <= 6 do
					local nx = cx + dirs[di][1];
					local ny = cy + dirs[di][2];
					local adj = Map.GetPlot(nx, ny);
					if adj ~= nil and adj:IsWater() == false and adj:GetPlotType() == PlotTypes.PLOT_LAND then
						if isTundraColAt(nx, ny) ~= true then
							table.insert(picks, adj);
						end
					end
					di = di + 1;
				end
				if #picks < 1 then
					break
				end
				local nxt = picks[Map.Rand(#picks, "Snow Ridge Step") + 1];
				nxt:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				nHill = nHill + 1;
				cx = nxt:GetX();
				cy = nxt:GetY();
				step = step + 1;
			end
		end
		ri = ri + 1;
	end
	local nLand = 0;
	local nSolid = 0;
	local hills = {};
	local hi = 1;
	while hi <= #land do
		local p = land[hi];
		if p:IsWater() == false then
			nSolid = nSolid + 1;
			local pt = p:GetPlotType();
			if pt == PlotTypes.PLOT_LAND then
				nLand = nLand + 1;
			elseif pt == PlotTypes.PLOT_HILLS then
				table.insert(hills, p);
			end
		end
		hi = hi + 1;
	end
	local nNeed = math.ceil(nSolid * 0.5);
	if nLand < nNeed and #hills > 0 then
		hills = GetShuffledCopyOfTable(hills);
		local far = {};
		local near = {};
		hi = 1;
		while hi <= #hills do
			local p = hills[hi];
			local touch = false;
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
				if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					touch = true;
					break
				end
				d = d + 1;
			end
			if touch then
				table.insert(near, p);
			else
				table.insert(far, p);
			end
			hi = hi + 1;
		end
		local queue = {};
		hi = 1;
		while hi <= #far do
			table.insert(queue, far[hi]);
			hi = hi + 1;
		end
		hi = 1;
		while hi <= #near do
			table.insert(queue, near[hi]);
			hi = hi + 1;
		end
		hi = 1;
		while nLand < nNeed and hi <= #queue do
			if queue[hi]:GetPlotType() == PlotTypes.PLOT_HILLS then
				queue[hi]:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				nLand = nLand + 1;
				nHill = nHill - 1;
			end
			hi = hi + 1;
		end
	end
	print("Standard snow relief: peaks=", nMtn, " hills=", nHill, " flat=", nLand, "/", nSolid);
end
------------------------------------------------------------------------------
function CapBarrierMountains()
	if IsOldSnow() == false and IsSnowBarrier() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local mtns = {};
	local y = 0;
	while y < iH do
		local tundra = {};
		local tc = GetSnowWrapTundraColumns(iW, y);
		local ti = 1;
		while ti <= #tc do
			tundra[tc[ti]] = true;
			ti = ti + 1;
		end
		local snowCols = GetSnowWrapColumns(iW, y);
		local ci = 1;
		while ci <= #snowCols do
			local x = snowCols[ci];
			if tundra[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					table.insert(mtns, plot);
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	local n = #mtns;
	if n <= 4 then
		print("Barrier mountains:", n);
		return
	end
	mtns = GetShuffledCopyOfTable(mtns);
	local k = 5;
	while k <= n do
		mtns[k]:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
		k = k + 1;
	end
	print("Barrier mountains capped:", n, "-> 4");
end
------------------------------------------------------------------------------
function CountSnowForestNeighbors(plot)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
			n = n + 1;
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function ForestTundraSeparatorResources()
	local deerID = GameInfoTypes["RESOURCE_DEER"];
	local furID = GameInfoTypes["RESOURCE_FUR"];
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil
				and plot:IsWater() == false
				and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
				and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
				local res = plot:GetResourceType(-1);
				if res == deerID or res == furID then
					local feat = plot:GetFeatureType();
					if feat ~= FeatureTypes.FEATURE_FOREST and feat ~= FeatureTypes.FEATURE_ICE and feat ~= FeatureTypes.FEATURE_JUNGLE then
						plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Tundra deer/fur forests:", n);
end
------------------------------------------------------------------------------
function AddSnowForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.forestPct < 1 then
		return
	end
	local barrierTerrain = BarrierTerrainType(cfg);
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local remaining = {};
	local y = 0;
	while y < iH do
		local snowCols = GetSnowWrapColumns(iW, y);
		local ci = 1;
		while ci <= #snowCols do
			local x = snowCols[ci];
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local plotType = plot:GetPlotType();
					if plot:GetTerrainType() == barrierTerrain
						and (plotType == PlotTypes.PLOT_LAND or plotType == PlotTypes.PLOT_HILLS)
						and plot:GetFeatureType() == FeatureTypes.NO_FEATURE
						and plot:GetResourceType(-1) == -1 then
						table.insert(remaining, plot);
					end
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	local n = #remaining;
	local target = math.floor(n * (cfg.forestPct / 100) + 0.5);
	local placed = 0;
	while placed < target and #remaining > 0 do
		local totalWeight = 0;
		local i = 1;
		while i <= #remaining do
			local neigh = CountSnowForestNeighbors(remaining[i]);
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			totalWeight = totalWeight + w;
			i = i + 1;
		end
		if totalWeight < 1 then
			break
		end
		local roll = Map.Rand(totalWeight, "Barrier Forest Cluster");
		i = 1;
		local picked = false;
		while i <= #remaining do
			local neigh = CountSnowForestNeighbors(remaining[i]);
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			if roll < w then
				remaining[i]:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
				table.remove(remaining, i);
				placed = placed + 1;
				picked = true;
				break
			end
			roll = roll - w;
			i = i + 1;
		end
		if picked == false then
			remaining[#remaining]:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
			table.remove(remaining, #remaining);
			placed = placed + 1;
		end
	end
	print("Barrier forests:", placed, "/", n);
end
------------------------------------------------------------------------------
function AddBarrierOases()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.oasisPctOfFlat < 1 then
		return
	end
	local barrierTerrain = BarrierTerrainType(cfg);
	local iW, iH = Map.GetGridSize();
	local snowCols = GetSnowWrapColumns(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local remaining = {};
	local y = 0;
	while y < iH do
		local ci = 1;
		while ci <= #snowCols do
			local x = snowCols[ci];
			if (not mirrored) or (x <= iW * 0.5) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetTerrainType() == barrierTerrain
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE
					and plot:GetResourceType(-1) == -1 then
					table.insert(remaining, plot);
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	local shuffled = GetShuffledCopyOfTable(remaining);
	local n = #shuffled;
	local target = math.floor(n * (cfg.oasisPctOfFlat / 100) + 0.5);
	local placed = 0;
	local i = 1;
	while i <= n and placed < target do
		local plot = shuffled[i];
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			if plot:CanHaveFeature(FeatureTypes.FEATURE_OASIS) then
				plot:SetFeatureType(FeatureTypes.FEATURE_OASIS, -1);
				placed = placed + 1;
			end
		end
		i = i + 1;
	end
	i = 1;
	while i <= n and placed < target do
		local plot = shuffled[i];
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			plot:SetFeatureType(FeatureTypes.FEATURE_OASIS, -1);
			placed = placed + 1;
		end
		i = i + 1;
	end
	print("Barrier oases:", placed, "/", n);
end
------------------------------------------------------------------------------
function FillMireSkip(iW)
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	return skip;
end
------------------------------------------------------------------------------
-- Row-aware sibling of FillMireSkip: on a tilted-mirror-axis climate the
-- barrier column set moves per row (see TiltedFoldMid), so a caller that
-- checks candidate plots row-by-row should use this instead of the flat
-- FillMireSkip mask, which is pinned to the constant vertical-line position
-- and misses the true barrier on every row the fold has drifted away from
-- center. Not swapped into FillMireSkip's ~40 existing callers wholesale
-- (unaudited blast radius); use directly in new/fixed per-row call sites.
function RowMireSkip(iW, y)
	local skip = {};
	local cols = GetSnowWrapColumns(iW, y);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW, y);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	return skip;
end
------------------------------------------------------------------------------
function FrostyHexNeighbors(x, y)
	if y % 2 == 0 then
		return {{0, 1}, {1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	end
	return {{1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}};
end
------------------------------------------------------------------------------
function ConnectInlandSeasToWest(plotTypes, iW, iH)
	if plotTypes == nil or IsStandardClimate() then
		return
	end
	local cfg = GetBarrierConfig();
	if cfg ~= nil and cfg.kind == "wasteland" then
		return
	end
	if cfg ~= nil and cfg.kind == "desert" then
		return
	end
	if Map.Rand(100, "Inland sea channel") >= 20 then
		return
	end
	print("Inland sea channel: yes");
	local maxX = math.floor(iW / 2);
	local salt = {};
	local qx = {};
	local qy = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= 1 do
			if plotTypes[y * iW + x + 1] == PlotTypes.PLOT_OCEAN then
				local k = y * iW + x;
				if salt[k] ~= true then
					salt[k] = true;
					table.insert(qx, x);
					table.insert(qy, y);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local qi = 1;
	while qi <= #qx do
		local cx = qx[qi];
		local cy = qy[qi];
		local dirs = FrostyHexNeighbors(cx, cy);
		local di = 1;
		while di <= 6 do
			local nx = cx + dirs[di][1];
			local ny = cy + dirs[di][2];
			if ny >= 0 and ny < iH and nx >= 0 and nx <= maxX then
				if plotTypes[ny * iW + nx + 1] == PlotTypes.PLOT_OCEAN then
					local k = ny * iW + nx;
					if salt[k] ~= true then
						salt[k] = true;
						table.insert(qx, nx);
						table.insert(qy, ny);
					end
				end
			end
			di = di + 1;
		end
		qi = qi + 1;
	end
	y = 0;
	while y < iH do
		local x = 2;
		while x <= maxX do
			if plotTypes[y * iW + x + 1] == PlotTypes.PLOT_OCEAN then
				if salt[y * iW + x] ~= true then
					local cx = x - 1;
					local nLand = 0;
					local hit = false;
					while cx >= 0 and nLand <= 5 do
						if plotTypes[y * iW + cx + 1] == PlotTypes.PLOT_OCEAN then
							if salt[y * iW + cx] == true then
								hit = true;
							end
							break
						end
						nLand = nLand + 1;
						cx = cx - 1;
					end
					if hit then
						local px = x - 1;
						while px > cx do
							if WaterAllowedAtXY(px, y) then
								plotTypes[y * iW + px + 1] = PlotTypes.PLOT_OCEAN;
							end
							px = px - 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function AddFrostyLayout()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	WeeveeDbg("AddFrostyLayout");
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	FrostyEnsureFrac(iW, iH);
	local nSnow = 0;
	local nTun = 0;
	local nPlains = 0;
	local nGrass = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local w = FrostyWarmth(x, y, iW, iH);
					local terr = TerrainTypes.TERRAIN_GRASS;
					if w < 0.22 then
						terr = TerrainTypes.TERRAIN_SNOW;
					elseif w < 0.36 then
						if Map.Rand(100, "Frosty Snow Tundra Mix") < 62 then
							terr = TerrainTypes.TERRAIN_SNOW;
						else
							terr = TerrainTypes.TERRAIN_TUNDRA;
						end
					elseif w < 0.50 then
						terr = TerrainTypes.TERRAIN_TUNDRA;
					elseif w < 0.62 then
						if Map.Rand(100, "Frosty Tundra Plains Mix") < 70 then
							terr = TerrainTypes.TERRAIN_TUNDRA;
						else
							terr = TerrainTypes.TERRAIN_PLAINS;
						end
					elseif w < 0.84 then
						terr = TerrainTypes.TERRAIN_PLAINS;
					else
						terr = TerrainTypes.TERRAIN_GRASS;
					end
					plot:SetTerrainType(terr, false, false);
					if terr == TerrainTypes.TERRAIN_SNOW then
						nSnow = nSnow + 1;
					elseif terr == TerrainTypes.TERRAIN_TUNDRA then
						nTun = nTun + 1;
					elseif terr == TerrainTypes.TERRAIN_PLAINS then
						nPlains = nPlains + 1;
					else
						nGrass = nGrass + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	FrostyAccentNorthCap(iW, iH, skip, mirrored);
	FrostyAccentNunataks(iW, iH, skip, mirrored);
	FrostyAccentGlacierTongue(iW, iH, skip, mirrored);
	SlashMireMountainBlobs(iW, iH, skip);
	FrostyShiftMountains(iW, iH, skip, mirrored);
	FrostyEnsureFrontMountains(iW, iH, skip, mirrored);
	print("Frosty terrain snow", nSnow, "tundra", nTun, "plains", nPlains, "grass", nGrass);
	WeeveeDbg("AddFrostyLayout done");
end
------------------------------------------------------------------------------
function FrostyEnsureFrac(iW, iH)
	if frostyFrac ~= nil then
		return
	end
	if iW == nil then
		iW, iH = Map.GetGridSize();
	end
	frostyFrac = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
end
------------------------------------------------------------------------------
function FrostyWarmth(x, y, iW, iH)
	FrostyEnsureFrac(iW, iH);
	local poleX = 0;
	local poleY = iH - 1;
	local frontX = math.floor(iW / 2) - 4;
	if frontX < 4 then
		frontX = iW - 1;
	end
	local maxD = Map.PlotDistance(poleX, poleY, frontX, 0);
	if maxD < 1 then
		maxD = 1;
	end
	local radial = Map.PlotDistance(x, y, poleX, poleY) / maxD;
	local south = 0;
	if iH > 1 then
		south = (iH - 1 - y) / (iH - 1);
	end
	local noise = 0;
	local hLo = frostyFrac:GetHeight(12);
	local hHi = frostyFrac:GetHeight(88);
	if hHi > hLo then
		noise = ((frostyFrac:GetHeight(x, y) - hLo) / (hHi - hLo) - 0.5) * 0.16;
	end
	local n = radial * 0.82 + south * 0.18 + noise;
	local yNorm = 0;
	if iH > 1 then
		yNorm = y / (iH - 1);
	end
	if yNorm > 0.90 then
		n = n - 0.14;
	elseif yNorm > 0.84 then
		n = n - 0.07;
	end
	if n < 0 then
		n = 0;
	end
	n = n + 0.05;
	if n > 1 then
		n = 1;
	end
	return n
end
------------------------------------------------------------------------------
function FrostyAccentNorthCap(iW, iH, skip, mirrored)
	local yMin = math.floor((iH - 1) * 0.92);
	local y = yMin;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local w = FrostyWarmth(x, y, iW, iH);
					if w < 0.46 then
						plot:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function FrostyAccentNunataks(iW, iH, skip, mirrored)
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() == PlotTypes.PLOT_LAND then
					local t = plot:GetTerrainType();
					local chance = 0;
					if t == TerrainTypes.TERRAIN_SNOW then
						chance = 14;
					elseif t == TerrainTypes.TERRAIN_TUNDRA then
						chance = 8;
					end
					if chance > 0 and Map.Rand(100, "Frosty Nunatak") < chance then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Frosty nunatak hills:", n);
end
------------------------------------------------------------------------------
function FrostyAccentGlacierTongue(iW, iH, skip, mirrored)
	local cands = {};
	local y = math.floor((iH - 1) * 0.70);
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW
					and FrostyWarmth(x, y, iW, iH) < 0.28 then
					table.insert(cands, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #cands < 4 then
		return
	end
	cands = GetShuffledCopyOfTable(cands);
	local seed = cands[1];
	local q = {seed};
	seed:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
	seed:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
	local grown = 1;
	local target = 7 + Map.Rand(6, "Frosty Glacier Size");
	local qi = 1;
	while qi <= #q and grown < target do
		local p = q[qi];
		qi = qi + 1;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
			if adj ~= nil and grown < target then
				local ax = adj:GetX();
				local ay = adj:GetY();
				if skip[ax] ~= true and MirrorOwnsPlot(ax, ay, mirrored, iW)
					and adj:IsWater() == false
					and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if Map.Rand(100, "Frosty Glacier Grow") < 58 then
						adj:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						adj:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
						table.insert(q, adj);
						grown = grown + 1;
					end
				end
			end
			d = d + 1;
		end
	end
	print("Frosty glacier tongue:", grown);
end
------------------------------------------------------------------------------
function FrostyShiftMountains(iW, iH, skip, mirrored)
	local xCenter = math.floor(iW / 2) - 4;
	local frontLo = xCenter - 2;
	local frontHi = xCenter + 2;
	local southY = math.floor(iH * 0.5);
	local function isFrontX(x)
		if skip[x] == true then
			return true
		end
		if x >= frontLo and x <= frontHi then
			return true
		end
		return false
	end
	local function adjMtn(x, y)
		local n = 0;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(x, y, d);
			if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
				n = n + 1;
			end
			d = d + 1;
		end
		return n
	end
	local nCut = 0;
	local y = 0;
	while y < southY do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) and isFrontX(x) == false then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					if Map.Rand(100, "Frosty South Mtn Cut") < 62 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						nCut = nCut + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nAdd = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) and isFrontX(x) == false then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
					local chance = 6;
					if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
						chance = 16;
					end
					local nM = adjMtn(x, y);
					if nM >= 2 then
						chance = 0;
					elseif nM == 1 then
						chance = chance + 10;
					end
					if chance > 0 and Map.Rand(100, "Frosty Snow Mtn") < chance then
						plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
						nAdd = nAdd + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Frosty mountains south cut:", nCut, " snow add:", nAdd);
end
------------------------------------------------------------------------------
function FrostyEnsureFrontMountains(iW, iH, skip, mirrored)
	local wrapN, centerN = ResolveSnowWrapWidths();
	if centerN < 1 then
		return
	end
	local mid = math.floor(iW / 2);
	local tundraX = mid - centerN / 2 - 1;
	local xLo = tundraX - 2;
	local xHi = tundraX;
	if xLo < 0 then
		xLo = 0;
	end
	local nAdd = 0;
	local y0 = 0;
	while y0 < iH do
		local y1 = y0 + 5;
		if y1 >= iH then
			y1 = iH - 1;
		end
		local nMtn = 0;
		local cands = {};
		local y = y0;
		while y <= y1 do
			local x = xLo;
			while x <= xHi do
				if skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false then
						if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
							nMtn = nMtn + 1;
						else
							table.insert(cands, plot);
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if nMtn < 2 and #cands > 0 then
			local nWant = 2 - nMtn;
			local ci = 1;
			while nWant > 0 and #cands > 0 do
				local pick = cands[1 + Map.Rand(#cands, "Frosty Front Gap")];
				pick:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
				nAdd = nAdd + 1;
				nWant = nWant - 1;
				local next = {};
				ci = 1;
				while ci <= #cands do
					if cands[ci] ~= pick then
						table.insert(next, cands[ci]);
					end
					ci = ci + 1;
				end
				cands = next;
			end
		end
		y0 = y0 + 3;
	end
	print("Frosty front gap mountains:", nAdd);
end
------------------------------------------------------------------------------
function TongueEnsureEconFrac()
	if tongueEconFrac ~= nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	tongueEconFrac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	tongueEconFrac2 = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
end
------------------------------------------------------------------------------
function TongueEconNoise(x, y, which)
	TongueEnsureEconFrac();
	local frac = tongueEconFrac;
	if which == 2 then
		frac = tongueEconFrac2;
	end
	local hLo = frac:GetHeight(12);
	local hHi = frac:GetHeight(88);
	if hHi <= hLo then
		return 0
	end
	return ((frac:GetHeight(x, y) - hLo) / (hHi - hLo) - 0.5) * 2;
end
------------------------------------------------------------------------------
function TongueEconKind(dist, x, y, jDepth, forestDepth)
	local jCut = jDepth + TongueEconNoise(x, y, 1) * 2.4;
	if jCut < 1.2 then
		jCut = 1.2;
	end
	local fCut = jCut + forestDepth + TongueEconNoise(x, y, 2) * 2.2;
	if dist <= jCut then
		return 1
	end
	if dist <= fCut then
		return 2
	end
	return 3
end
------------------------------------------------------------------------------
function EconBandBleed(band, iW, iH, skip, mirrored)
	local pass = 1;
	while pass <= 2 do
		local toJ = {};
		local toF = {};
		local toP = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local i = y * iW + x + 1;
					local b = band[i];
					if b == 1 or b == 2 or b == 3 then
						local dirs = FrostyHexNeighbors(x, y);
						local di = 1;
						while di <= 6 do
							local nx = x + dirs[di][1];
							local ny = y + dirs[di][2];
							local np = Map.GetPlot(nx, ny);
							if np ~= nil and skip[nx] ~= true and ((not mirrored) or (nx <= iW * 0.5)) then
								if np:IsWater() == false and np:GetTerrainType() ~= TerrainTypes.TERRAIN_TUNDRA then
									local ai = ny * iW + nx + 1;
									local ab = band[ai];
									if b == 1 and ab == 2 then
										if Map.Rand(100, "Econ Jungle Bleed") < 38 then
											toJ[ai] = true;
										end
									elseif b == 2 and ab == 3 then
										if Map.Rand(100, "Econ Forest Bleed") < 34 then
											toF[ai] = true;
										end
									elseif b == 2 and ab == 1 then
										if Map.Rand(100, "Econ Jungle Back") < 16 then
											toF[ai] = true;
										end
									elseif b == 3 and ab == 2 then
										if Map.Rand(100, "Econ Plains Bleed") < 22 then
											toP[ai] = true;
										end
									end
								end
							end
							di = di + 1;
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local i, _;
		for i, _ in pairs(toJ) do
			if toF[i] == nil and toP[i] == nil and band[i] == 2 then
				band[i] = 1;
			end
		end
		for i, _ in pairs(toF) do
			if toJ[i] == nil and toP[i] == nil then
				if band[i] == 3 or band[i] == 1 then
					band[i] = 2;
				end
			end
		end
		for i, _ in pairs(toP) do
			if toJ[i] == nil and toF[i] == nil and band[i] == 2 then
				band[i] = 3;
			end
		end
		pass = pass + 1;
	end
end
------------------------------------------------------------------------------
function PaintEconBands(band, iW, iH, skip, mirrored)
	TongueEnsureEconFrac();
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local i = y * iW + x + 1;
				local b = band[i];
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetTerrainType() ~= TerrainTypes.TERRAIN_TUNDRA then
					if plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if b == 1 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
						elseif b == 2 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
							plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						elseif b == 3 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local forestCut = tongueEconFrac2:GetHeight(38);
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local i = y * iW + x + 1;
				if band[i] == 2 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
						if tongueEconFrac2:GetHeight(x, y) >= forestCut then
							if Map.Rand(100, "Econ Forest Clump") < 72 then
								plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
							end
						elseif Map.Rand(100, "Econ Forest Speck") < 16 then
							plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local i = y * iW + x + 1;
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
					local nJ = 0;
					local nF = 0;
					local dirs = FrostyHexNeighbors(x, y);
					local di = 1;
					while di <= 6 do
						local np = Map.GetPlot(x + dirs[di][1], y + dirs[di][2]);
						if np ~= nil then
							if np:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
								nJ = nJ + 1;
							elseif np:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
								nF = nF + 1;
							end
						end
						di = di + 1;
					end
					if band[i] == 1 and nJ >= 2 then
						plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
					elseif band[i] == 2 and nF >= 2 then
						plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
						plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Live-map (Map.GetPlot) mirrored mountain placement, for pipeline stages
-- after GeneratePlotTypes' temporary plotTypes array is gone -- Bramble's
-- separator shape isn't known until AddBrambleLayout runs (GenerateTerrain
-- stage), so its contact-point mountains can't use the array-based
-- PlaceMirroredMountainCapped the other climates' front mountains use.
-- Writes both the tile and its 180-rotation mirror immediately (rather than
-- west-only + trust the final late mirror pass) so AddRivers, which runs
-- right after GenerateTerrain, sees the real mountain on both sides.
function BramblePlaceMirroredMountain(x, y, cap)
	local iW, iH = Map.GetGridSize();
	if x < 0 or x >= iW or y < 0 or y >= iH then
		return false
	end
	local plot = Map.GetPlot(x, y);
	if plot == nil or plot:IsWater() or plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	local mx, my = iW - x - 1, iH - y - 1;
	local mp = Map.GetPlot(mx, my);
	if mp == nil then
		return false
	end
	local prevA, prevB = plot:GetPlotType(), mp:GetPlotType();
	plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
	mp:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
	if LiveMountainClumpSize(x, y, cap) > cap or LiveMountainClumpSize(mx, my, cap) > cap then
		plot:SetPlotType(prevA, false, false);
		mp:SetPlotType(prevB, false, false);
		return false
	end
	return true
end
------------------------------------------------------------------------------
-- Mountains across most of the contact area, then 2-4 big (4+ row) openings
-- slashed into that wall -- the inverse of the earlier sparse-points
-- design. Fills first (most rows get a mountain at the tundra/jungle edge,
-- messy single-tile-or-small-spike, random face each time), then clears
-- whatever landed inside each carved opening, reverting strip tiles to
-- proper valley-floor tundra (matching AddBrambleLayout's hill-rim
-- formula) and non-strip tiles to flat land (jungle repaints those
-- properly later regardless of plot type).
function BramblePlaceContactMountains(iW, iH, cap)
	local yLo, yHi = 2, iH - 3;
	if yHi < yLo then
		return
	end
	local span = yHi - yLo + 1;
	-- Exactly 2 gaps, 4-6 rows each, chosen FIRST and locked as non-overlapping
	-- exclusion zones -- the wall is then built only in what's left over. This
	-- (rather than filling everything and carving gaps out afterward) is what
	-- guarantees the gaps can never collectively eat the whole front: there
	-- are only ever 2 of them, each capped at 6 rows, so a 22-row span (the
	-- real Small-map front) always has most of its rows left over for wall.
	local gaps = {};
	local function overlapsGap(s, e)
		local i = 1;
		while i <= #gaps do
			local g = gaps[i];
			if s <= g[2] and e >= g[1] then
				return true
			end
			i = i + 1;
		end
		return false
	end
	local gi = 1;
	while gi <= 2 do
		local gapLen = 4 + Map.Rand(3, "Bramble Contact Gap Len"); -- 4-6
		if gapLen > span then
			gapLen = span;
		end
		local attempt = 1;
		while attempt <= 20 do
			local gapStart = yLo + Map.Rand(span - gapLen + 1, "Bramble Contact Gap Start");
			local gapEnd = gapStart + gapLen - 1;
			if overlapsGap(gapStart, gapEnd) == false then
				table.insert(gaps, {gapStart, gapEnd});
				break
			end
			attempt = attempt + 1;
		end
		gi = gi + 1;
	end
	local function inGap(y)
		local i = 1;
		while i <= #gaps do
			if y >= gaps[i][1] and y <= gaps[i][2] then
				return true
			end
			i = i + 1;
		end
		return false
	end
	-- Strong noisy ridges: runs of 3-8 consecutive rows, one mountain per row,
	-- with an outward/inward offset that wanders row to row (never a razor-
	-- straight line) plus an occasional single-row skip mid-ridge for a
	-- "splintered" look. Each ridge picks a random face (east/west side of
	-- the strip) and a random chance to bite straight into the tundra edge.
	-- Ridges are separated by a short 0-1 row breather (distinct from the 2
	-- big designated gaps) so the wall reads as several ridge segments
	-- splintered along the line, not one unbroken bar.
	local y = yLo;
	while y <= yHi do
		if inGap(y) then
			y = y + 1;
		else
			local onEastFace = (Map.Rand(2, "Bramble Contact Face") == 0);
			local outDir = onEastFace and 1 or -1;
			local ridgeLen = 3 + Map.Rand(6, "Bramble Contact Ridge Len"); -- 3-8
			local offset = 0;
			local step = 1;
			while step <= ridgeLen and y <= yHi and inGap(y) == false do
				offset = offset + Map.Rand(3, "Bramble Contact Wander") - 1; -- -1,0,+1
				if offset < -1 then
					offset = -1;
				end
				if offset > 2 then
					offset = 2;
				end
				-- Small chance to skip this row entirely -- the "splinter" in
				-- an otherwise near-solid ridge.
				if Map.Rand(100, "Bramble Contact Splinter") >= 12 then
					local baseX = onEastFace and (brambleHi[y] + 1) or (brambleLo[y] - 1);
					local startX = baseX + offset * outDir;
					if Map.Rand(100, "Bramble Contact Bite") < 15 then
						startX = onEastFace and brambleHi[y] or brambleLo[y];
					end
					BramblePlaceMirroredMountain(startX, y, cap);
				end
				y = y + 1;
				step = step + 1;
			end
			y = y + Map.Rand(2, "Bramble Contact Pause"); -- 0-1 row breather
		end
	end
end
------------------------------------------------------------------------------
-- Paints Bramble's separator (flat tundra, no random mountain/hill roll --
-- unlike the generic barrier painter) directly from brambleLo/brambleHi,
-- then drops the contact-point mountains. West side only; the standard
-- end-of-generation mirror pass reproduces this on east, same as every
-- other climate (see feedback_west_side_only_rules).
function AddBrambleLayout()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "bramble" then
		return
	end
	WeeveeDbg("AddBrambleLayout");
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	BrambleEnsureShape();
	-- Valley cross-section, flat center out to the rim: a flat tundra floor
	-- in the middle of the strip, hills toward each edge (where the
	-- contact-point mountains sit) -- the "old version" look the user
	-- wants back, instead of the strip reading as uniformly flat.
	local y = 0;
	while y < iH do
		local lo, hi = brambleLo[y], brambleHi[y];
		local width = hi - lo + 1;
		local hillBand = math.max(1, math.floor(width / 3));
		local x = lo;
		while x <= hi do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local distFromEdge = math.min(x - lo, hi - x);
					local wantType = PlotTypes.PLOT_LAND;
					if distFromEdge < hillBand then
						wantType = PlotTypes.PLOT_HILLS;
					end
					if plot:GetPlotType() ~= wantType then
						plot:SetPlotType(wantType, false, false);
					end
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
					plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	BramblePlaceContactMountains(iW, iH, FRONT_MOUNTAIN_CLUMP_CAP);
	BrambleApplyFoothills(iW, iH, mirrored, 80);
	WeeveeDbg("AddBrambleLayout done");
end
------------------------------------------------------------------------------
-- Tectonic-realism pass for the contact-point mountains: any flat tile
-- adjacent to one has a chance to become hills. Live-plot equivalent of the
-- other climates' applyFoothillAt (that one is local to GeneratePlotTypes
-- and runs before Bramble's mountains exist, so it never sees them).
function BrambleApplyFoothills(iW, iH, mirrored, chance)
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsFlatlands() then
					local dirs = HexDirsForY(y);
					local nearMtn = false;
					local di = 1;
					while di <= 6 do
						local nx, ny = x + dirs[di][1], y + dirs[di][2];
						if nx >= 0 and nx < iW and ny >= 0 and ny < iH then
							local np = Map.GetPlot(nx, ny);
							if np ~= nil and np:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
								nearMtn = true;
								break
							end
						end
						di = di + 1;
					end
					if nearMtn and Map.Rand(100, "Bramble Foothill") < chance then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Safety net for the "every tundra tile (outside the corner flavor) touches
-- jungle, mountain, or more tundra" rule: after the tapered jungle band and
-- the contact-point mountains are both down, walk every separator tile and
-- force any remaining flat/water-free neighbor to jungle. Mostly a no-op in
-- practice (the taper's minimum depth already covers the immediate ring)
-- but makes the guarantee exact regardless of how a mountain spike happened
-- to eat into that ring.
function BrambleFillTundraContactGaps(iW, iH, mirrored)
	local y = 0;
	while y < iH do
		local x = brambleLo[y];
		while x <= brambleHi[y] do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local dirs = HexDirsForY(y);
				local di = 1;
				while di <= 6 do
					local nx, ny = x + dirs[di][1], y + dirs[di][2];
					if nx >= 0 and nx < iW and ny >= 0 and ny < iH and (nx < brambleLo[ny] or nx > brambleHi[ny]) then
						local np = Map.GetPlot(nx, ny);
						if np ~= nil and np:IsWater() == false and np:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
							and np:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE then
							-- Jungle is plains-only on Bramble, never grass;
							-- hills here to match the core ring's "hill
							-- jungle" (this fills gaps right at the contact).
							if np:GetTerrainType() ~= TerrainTypes.TERRAIN_PLAINS then
								np:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							end
							if np:GetPlotType() ~= PlotTypes.PLOT_HILLS then
								np:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
							end
							np:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
						end
					end
					di = di + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Thick and stable right at the tundra edge (deterministic, always fills,
-- and thicker than before), then a wild zone that reaches further out --
-- but the wild reach is a row-to-row correlated random walk (like a
-- smoothed width profile), not an independent roll per row/depth, so it
-- grows into connected bulges instead of single-row spikes poking into the
-- tundra. West and east faces walk independently. Finishes with
-- BrambleFillTundraContactGaps for the hard "every tundra tile touches
-- jungle/mountain/tundra" guarantee.
-- Valley cross-section continued past the mountains: the core ring
-- (BRAMBLE_JUNGLE_CORE_DEPTH) is jungle-on-hills, matching the tundra
-- rim's hills on the other side of the mountain wall; the wild zone beyond
-- it is a genuine hill/flat mix rather than uniform flat, so the "frayed"
-- outer edge still reads as terrain, not just a feature painted on a flat
-- plane.
function BrambleAddJungle(iW, iH, mirrored)
	local baseDepth = BRAMBLE_JUNGLE_CORE_DEPTH;
	local wildMaxExtra = 5;
	local function paintIfLand(x, y, wantHills)
		if MirrorOwnsPlot(x, y, mirrored, iW) == false then
			return
		end
		local plot = Map.GetPlot(x, y);
		if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
			and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			-- Jungle is plains-only on Bramble, never grass.
			if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_PLAINS then
				plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
			end
			local wantType = wantHills and PlotTypes.PLOT_HILLS or PlotTypes.PLOT_LAND;
			if plot:GetPlotType() ~= wantType then
				plot:SetPlotType(wantType, false, false);
			end
			plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
		end
	end
	-- The wild reach is entirely a row-to-row correlated random walk on the
	-- DEPTH value -- once a row's depth is decided, it fills solid up to
	-- that depth (no per-tile hole-punching). Per-tile patchiness inside
	-- the band was the actual cause of the jagged/disconnected look: even
	-- with a smoothed depth, independent per-tile rolls left single-tile
	-- gaps right at the noisiest (outermost) edge, reading as stray spikes
	-- rather than a connected bulge.
	local function walkExtra(extra)
		local delta = Map.Rand(3, "Bramble Jungle Wild Step") - 1;
		if Map.Rand(100, "Bramble Jungle Wild Burst") < 8 then
			delta = delta + (Map.Rand(3, "Bramble Jungle Wild Burst Dir") - 1);
		end
		extra = extra + delta;
		if extra < 0 then
			extra = 0;
		end
		if extra > wildMaxExtra then
			extra = wildMaxExtra;
		end
		return extra;
	end
	local extraW, extraE = 0, 0;
	local y = 0;
	while y < iH do
		extraW = walkExtra(extraW);
		extraE = walkExtra(extraE);
		local depthW, depthE = baseDepth + extraW, baseDepth + extraE;
		local d = 1;
		while d <= depthW do
			local wantHills = (d <= baseDepth) or (Map.Rand(100, "Bramble Jungle Wild Hill") < 45);
			paintIfLand(brambleLo[y] - d, y, wantHills);
			d = d + 1;
		end
		d = 1;
		while d <= depthE do
			local wantHills = (d <= baseDepth) or (Map.Rand(100, "Bramble Jungle Wild Hill") < 45);
			paintIfLand(brambleHi[y] + d, y, wantHills);
			d = d + 1;
		end
		y = y + 1;
	end
	BrambleFillTundraContactGaps(iW, iH, mirrored);
	BrambleClearMountainNeighborStrays(iW, iH, mirrored);
end
------------------------------------------------------------------------------
-- Any Bramble-placed mountain can leave an orphaned neighbor: a contact
-- mountain that "bites" into the strip (or whose messy spike wanders to a
-- wider row) can strand a genuine strip tundra tile mid-row instead of at
-- the edge (BrambleFillTundraContactGaps only looks OUTSIDE
-- [brambleLo,brambleHi], so it never touches those); separately, a spike
-- that wanders further from the strip than THAT row's jungle depth happens
-- to reach leaves BrambleApplyFoothills' hill conversion (which checks
-- every mountain neighbor regardless of distance) with nothing to pair it
-- with -- a hills tile with its original stock terrain (plains/grass) and
-- no feature at all, never folded into the jungle. This checks all 6
-- neighbors of every mountain in a narrow band around the strip (not the
-- whole map, so it can't reach the corner-flavor patches) and folds any
-- still-bare one into jungle, keeping whatever plot type (hills or flat)
-- it already has -- matching the "mixed hill/flat" jungle look rather than
-- forcing it flat.
function BrambleClearMountainNeighborStrays(iW, iH, mirrored)
	-- True if (x,y) still has at least one in-strip neighbor that's real
	-- land (not mountain) -- i.e. it's still part of the contiguous valley
	-- floor, not cut off by mountains on every strip-facing side.
	local function stillConnectedToFloor(x, y)
		local dirs = HexDirsForY(y);
		local di = 1;
		while di <= 6 do
			local mx, my = x + dirs[di][1], y + dirs[di][2];
			if my >= 0 and my < iH and mx >= brambleLo[my] and mx <= brambleHi[my] then
				local mp = Map.GetPlot(mx, my);
				if mp ~= nil and mp:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					return true
				end
			end
			di = di + 1;
		end
		return false
	end
	local buffer = 4;
	local y = 0;
	while y < iH do
		local xLo = math.max(0, brambleLo[y] - buffer);
		local xHi = math.min(iW - 1, brambleHi[y] + buffer);
		local x = xLo;
		while x <= xHi do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					local dirs = HexDirsForY(y);
					local di = 1;
					while di <= 6 do
						local nx, ny = x + dirs[di][1], y + dirs[di][2];
						if nx >= 0 and nx < iW and ny >= 0 and ny < iH then
							local np = Map.GetPlot(nx, ny);
							if np ~= nil and np:IsWater() == false and np:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
								and np:GetFeatureType() == FeatureTypes.NO_FEATURE then
								local insideStrip = (nx >= brambleLo[ny] and nx <= brambleHi[ny]);
								-- Outside the strip: always safe to fold into
								-- jungle (nothing else it could legitimately
								-- be). Inside the strip: only if it's
								-- actually stranded -- otherwise it's
								-- ordinary valley floor and must stay tundra.
								if insideStrip == false or stillConnectedToFloor(nx, ny) == false then
									if np:GetTerrainType() ~= TerrainTypes.TERRAIN_PLAINS then
										np:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
									end
									np:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
								end
							end
						end
						di = di + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
-- Realism flourish in the two econ-zone corners farthest from the
-- separator: one gets a touch of desert, the other a touch of tundra
-- (picked randomly -- GetClimateLatitudeAtPlot is symmetric about the map's
-- vertical center, so it can't tell which pole is "colder"). Excluded from
-- the 7-tile-from-tundra start-distance rule as agreed (this is flavor, not
-- part of the separator). 1-3 spots per flavor, capped at 4 total for
-- variance without cluttering the corner. Desert uses loose, bigger curved
-- strokes scattered around the corner region; tundra uses blocky Tetris-L
-- shapes that always anchor right at the true corner, hugging it without
-- filling it solid. Neither stops the walk at water, so a stroke that
-- crosses a strait keeps painting on the far side -- mainland and a nearby
-- island can both pick up the flavor.
function BrambleCornerFlavor(iW, iH, mirrored)
	-- forestChance: the stock feature generator already ran (AddFeatures
	-- dispatches this well after featuregen:AddFeatures) before this paints
	-- fresh terrain over whatever was there, wiping any forest it placed --
	-- without re-rolling forest ourselves here, these patches would always
	-- end up bare, unlike naturally-generated tundra elsewhere (Standard)
	-- which gets its forest before the terrain is finalized.
	local function paintTile(x, y, terrain, forestChance)
		if x < 0 or x >= iW or y < 0 or y >= iH then
			return
		end
		if MirrorOwnsPlot(x, y, mirrored, iW) == false then
			return
		end
		if x >= brambleLo[y] and x <= brambleHi[y] then
			return
		end
		local plot = Map.GetPlot(x, y);
		if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
			plot:SetTerrainType(terrain, false, false);
			if forestChance ~= nil and forestChance > 0 and Map.Rand(100, "Bramble Corner Forest") < forestChance then
				plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
			else
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			end
		end
	end
	local function brushWidth(x, y, terrain, width, forestChance)
		local wi = 1;
		while wi < width do
			local dirs = HexDirsForY(y);
			local pick = dirs[1 + Map.Rand(6, "Bramble Corner Brush Dir")];
			paintTile(x + pick[1], y + pick[2], terrain, forestChance);
			wi = wi + 1;
		end
	end
	-- Narrows the brush toward the middle of a stroke/leg (full width at
	-- both ends, down to just the spine tile in the middle third) so each
	-- stroke reads as two thicker chunks loosely joined by a thin waist
	-- rather than one solid blob.
	local function midThinWidth(step, total, width)
		if total <= 2 then
			return width;
		end
		local midPos = (total + 1) / 2;
		local halfSpan = total / 2;
		local midFrac = 1 - math.abs(step - midPos) / halfSpan;
		if midFrac > 0.55 then
			return 1;
		elseif midFrac > 0.25 then
			return math.max(1, width - 1);
		end
		return width;
	end
	local function paintDesertStroke(sy, dirSign, terrain)
		local strokeLen = 5 + Map.Rand(6, "Bramble Smear Len");
		local width = 2 + Map.Rand(3, "Bramble Smear Width");
		local x, y = Map.Rand(8, "Bramble Smear StartX"), sy;
		local step = 1;
		while step <= strokeLen do
			paintTile(x, y, terrain, nil);
			brushWidth(x, y, terrain, midThinWidth(step, strokeLen, width), nil);
			-- Advance mostly along the edge (dirSign), with an occasional
			-- sideways nudge for a loose, gentle curve.
			local dirs = HexDirsForY(y);
			local best, bestScore = dirs[1], nil;
			local di = 1;
			while di <= 6 do
				local score = dirs[di][2] * dirSign;
				if bestScore == nil or score > bestScore then
					bestScore = score;
					best = dirs[di];
				end
				di = di + 1;
			end
			local pick = best;
			if Map.Rand(100, "Bramble Smear Curve") < 40 then
				pick = dirs[1 + Map.Rand(6, "Bramble Smear Curve Dir")];
			end
			x, y = x + pick[1], y + pick[2];
			step = step + 1;
		end
	end
	local function paintTundraL(cornerY, dirSign, terrain)
		local leg1 = 2 + Map.Rand(3, "Bramble L Leg1");
		local leg2 = 3 + Map.Rand(4, "Bramble L Leg2");
		local width = 1 + Map.Rand(2, "Bramble L Width");
		local x = 0;
		local y = cornerY + (Map.Rand(3, "Bramble L Y Jitter") - 1);
		if y < 0 then
			y = 0;
		end
		if y > iH - 1 then
			y = iH - 1;
		end
		-- Leg 1: straight out from the coast, anchored at the corner.
		local step = 1;
		while step <= leg1 do
			paintTile(x, y, terrain, 22);
			brushWidth(x, y, terrain, midThinWidth(step, leg1, width), 22);
			x = x + 1;
			step = step + 1;
		end
		-- Sharp bend, then leg 2 straight along the edge toward the map's
		-- vertical middle -- the Tetris-L silhouette.
		step = 1;
		while step <= leg2 do
			paintTile(x, y, terrain, 22);
			brushWidth(x, y, terrain, midThinWidth(step, leg2, width), 22);
			y = y + dirSign;
			if y < 0 or y >= iH then
				break
			end
			step = step + 1;
		end
	end
	local nDesert = 1 + Map.Rand(3, "Bramble Corner N Desert");
	local nTundra = 1 + Map.Rand(3, "Bramble Corner N Tundra");
	if nDesert + nTundra > 4 then
		nTundra = 4 - nDesert;
		if nTundra < 1 then
			nTundra = 1;
			nDesert = 3;
		end
	end
	local desertY, tundraY = 0, iH - 1;
	if Map.Rand(2, "Bramble Corner Pick") == 0 then
		desertY, tundraY = iH - 1, 0;
	end
	local desertDir = (desertY == 0) and 1 or -1;
	local tundraDir = (tundraY == 0) and 1 or -1;
	local yJitterMax = math.floor(iH * 0.12) + 1;
	local i = 1;
	while i <= nDesert do
		local sy = desertY + desertDir * Map.Rand(yJitterMax, "Bramble Desert Y Jitter");
		if sy < 0 then
			sy = 0;
		end
		if sy > iH - 1 then
			sy = iH - 1;
		end
		paintDesertStroke(sy, desertDir, TerrainTypes.TERRAIN_DESERT);
		i = i + 1;
	end
	i = 1;
	while i <= nTundra do
		paintTundraL(tundraY, tundraDir, TerrainTypes.TERRAIN_TUNDRA);
		i = i + 1;
	end
end
------------------------------------------------------------------------------
-- Rest of the econ zone: mostly plains, some grass, a little forest -- a
-- plausible-ish falloff away from the jungle border rather than vanilla's
-- latitude-only grass/plains/desert split. Driven by two fractals sampled
-- per tile (grass patches, forest patches) instead of an independent
-- per-tile roll, which read as pixel-noise speckle rather than natural
-- patches.
function BrambleEconGradient(iW, iH, mirrored)
	local terrFrac = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
	local grassHigh = terrFrac:GetHeight(72);
	local forestFrac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	local forestHigh = forestFrac:GetHeight(85);
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if MirrorOwnsPlot(x, y, mirrored, iW) and (x < brambleLo[y] or x > brambleHi[y]) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetFeatureType() ~= FeatureTypes.FEATURE_JUNGLE then
					if terrFrac:GetHeight(x, y) >= grassHigh then
						plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
					else
						plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
					end
					if plot:GetFeatureType() == FeatureTypes.NO_FEATURE and forestFrac:GetHeight(x, y) >= forestHigh then
						plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	BrambleCornerFlavor(iW, iH, mirrored);
end
------------------------------------------------------------------------------
function AddBrambleFeatures()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "bramble" then
		return
	end
	WeeveeDbg("AddBrambleFeatures");
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	BrambleEnsureShape();
	BrambleAddJungle(iW, iH, mirrored);
	BrambleEconGradient(iW, iH, mirrored);
	-- Diagnostic: land vs. jungle-covered land, west half only. If a future
	-- "no valid start" report recurs, this tells us whether jungle coverage
	-- is still eating the whole econ zone before we go looking anywhere else.
	local nLand, nJungle = 0, 0;
	local yy = 0;
	while yy < iH do
		local xx = 0;
		while xx < iW do
			if MirrorOwnsPlot(xx, yy, mirrored, iW) then
				local p = Map.GetPlot(xx, yy);
				if p ~= nil and p:IsWater() == false and p:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					nLand = nLand + 1;
					if p:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
						nJungle = nJungle + 1;
					end
				end
			end
			xx = xx + 1;
		end
		yy = yy + 1;
	end
	local diagLine = "Bramble jungle coverage: west land=" .. nLand .. " jungle=" .. nJungle
		.. " (" .. string.format("%.1f", 100 * nJungle / math.max(1, nLand)) .. "%)";
	print(diagLine);
	WeeveeDbg(diagLine);
	WeeveeDbg("AddBrambleFeatures done");
end
------------------------------------------------------------------------------
-- Post-hoc safety net: clears any feature that ended up on the separator
-- itself (e.g. from the stock feature generator running before Bramble's
-- own painting is mirrored). Called late in StartPlotSystem.
function StripBrambleSeparatorFeatures()
	if IsBramble() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	BrambleEnsureShape();
	local y = 0;
	while y < iH do
		local x = brambleLo[y];
		while x <= brambleHi[y] do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
					plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function AddFrostyForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	FrostyEnsureFrac(iW, iH);
	local snowPlots = {};
	local tundraPlots = {};
	local plainsPlots = {};
	local grassPlots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
					local t = plot:GetTerrainType();
					if t == TerrainTypes.TERRAIN_SNOW then
						if FrostyWarmth(x, y, iW, iH) > 0.10 then
							table.insert(snowPlots, plot);
						end
					elseif t == TerrainTypes.TERRAIN_TUNDRA then
						table.insert(tundraPlots, plot);
					elseif t == TerrainTypes.TERRAIN_PLAINS then
						if y > 5 or FrostyWarmth(x, y, iW, iH) < 0.80 then
							table.insert(plainsPlots, plot);
						end
					elseif t == TerrainTypes.TERRAIN_GRASS then
						if y > 5 or FrostyWarmth(x, y, iW, iH) < 0.80 then
							table.insert(grassPlots, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	PlaceClusteredFeature(snowPlots, FeatureTypes.FEATURE_FOREST, 17, "Frosty Snow Forest");
	PlaceClusteredFeature(tundraPlots, FeatureTypes.FEATURE_FOREST, 52, "Frosty Tundra Forest");
	PlaceClusteredFeature(plainsPlots, FeatureTypes.FEATURE_FOREST, 24, "Frosty Plains Forest");
	PlaceClusteredFeature(grassPlots, FeatureTypes.FEATURE_FOREST, 34, "Frosty Grass Forest");
end
------------------------------------------------------------------------------
function AddFrostyIce()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local frontX = math.floor(iW / 2) - 4;
	if frontX < 1 then
		frontX = 1;
	end
	local n = 0;
	local y = 0;
	while y < iH do
		local fromTop = (iH - 1) - y;
		if fromTop < 6 then
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
						local xN = x / frontX;
						if xN > 1 then
							xN = 1;
						end
						local rowN = 0;
						if fromTop > 0 then
							rowN = fromTop / 5;
						end
						if rowN > 1 then
							rowN = 1;
						end
						local chance = math.floor(88 * (1 - rowN * 0.80) * (1 - xN * 0.58));
						if plot:IsLake() then
							chance = chance + 10;
						elseif plot:IsAdjacentToLand() == false then
							chance = math.floor(chance * 0.50);
						end
						if Map.Rand(100, "Frosty Ice Gap") < 22 then
							chance = math.floor(chance * 0.28);
						end
						if chance > 0 and Map.Rand(100, "Frosty Ice") < chance then
							plot:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
							n = n + 1;
						end
					end
				end
				x = x + 1;
			end
		end
		y = y + 1;
	end
	print("Frosty ice:", n);
end
------------------------------------------------------------------------------
function AddFrostySouthJungle()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	FrostyEnsureFrac(iW, iH);
	local function jungleOk(plot)
		if plot == nil or plot:IsWater() or plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			return false
		end
		local t = plot:GetTerrainType();
		if t ~= TerrainTypes.TERRAIN_GRASS and t ~= TerrainTypes.TERRAIN_PLAINS then
			return false
		end
		local feat = plot:GetFeatureType();
		if feat ~= FeatureTypes.NO_FEATURE and feat ~= FeatureTypes.FEATURE_FOREST then
			return false
		end
		return true
	end
	local function jungleWarm(x, y)
		local w = FrostyWarmth(x, y, iW, iH);
		if w < 0.76 then
			return 0
		end
		local n = math.floor((w - 0.76) / 0.24 * 100);
		if n > 100 then
			n = 100;
		end
		return n
	end
	local function paintJungle(plot)
		plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
		plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1);
	end
	local n = 0;
	local x = 0;
	while x < iW do
		if skip[x] ~= true and MirrorOwnsPlot(x, 0, mirrored, iW) then
			local plot = Map.GetPlot(x, 0);
			local warm = jungleWarm(x, 0);
			if jungleOk(plot) and warm > 0 then
				local chance = warm;
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(x, 0, d);
					if adj ~= nil and adj:GetY() == 0 and adj:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
						chance = chance + 18;
					end
					d = d + 1;
				end
				if chance > 96 then
					chance = 96;
				end
				if Map.Rand(100, "Frosty Edge Jungle") < chance then
					paintJungle(plot);
					n = n + 1;
				end
			end
		end
		x = x + 1;
	end
	x = 0;
	while x < iW do
		if skip[x] ~= true and MirrorOwnsPlot(x, 0, mirrored, iW) then
			local plot = Map.GetPlot(x, 0);
			if jungleOk(plot) and jungleWarm(x, 0) >= 50 then
				local d = 0;
				local hug = false;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(x, 0, d);
					if adj ~= nil and adj:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
						hug = true;
					end
					d = d + 1;
				end
				if hug then
					paintJungle(plot);
					n = n + 1;
				end
			end
		end
		x = x + 1;
	end
	local y = 1;
	while y <= 5 and y < iH do
		x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				local warm = jungleWarm(x, y);
				if jungleOk(plot) and warm >= 22 then
					local hug = false;
					local d = 0;
					while d < DirectionTypes.NUM_DIRECTION_TYPES do
						local adj = PlotDirNoXWrap(x, y, d);
						if adj ~= nil and adj:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
							hug = true;
						end
						d = d + 1;
					end
					if hug then
						local chance = math.floor((62 - y * 10) * (0.30 + warm / 140));
						if chance < 8 then
							chance = 8;
						end
						if Map.Rand(100, "Frosty Jungle Grow") < chance then
							paintJungle(plot);
							n = n + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Frosty south jungle:", n);
end
------------------------------------------------------------------------------
function CountAdjacentTerrain(plot, terrainType)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetTerrainType() == terrainType then
			n = n + 1;
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function MurkIceColumnOk(x, skip, iW, mirrored)
	if mirrored and x > iW * 0.5 then
		return false
	end
	if skip[x] == true and x > 2 and x < iW - 3 then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function GrowMurkIceArm(plot, iH, skip, iW, mirrored)
	local steps = 0;
	while plot ~= nil and steps < 2 do
		local best = nil;
		local bestY = plot:GetY();
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
			if adj ~= nil and adj:IsWater() and adj:GetFeatureType() ~= FeatureTypes.FEATURE_ICE then
				local ax = adj:GetX();
				local ay = adj:GetY();
				if ay < plot:GetY() and ay >= iH - 3 and MurkIceColumnOk(ax, skip, iW, mirrored) then
					if best == nil or ay < bestY or (ay == bestY and Map.Rand(2, "Mire Ice Arm Tie") == 0) then
						best = adj;
						bestY = ay;
					end
				end
			end
			d = d + 1;
		end
		if best == nil then
			break
		end
		best:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
		if Map.Rand(100, "Mire Ice Arm Width") < 18 then
			local sd = 0;
			while sd < DirectionTypes.NUM_DIRECTION_TYPES do
				local side = PlotDirNoXWrap(best:GetX(), best:GetY(), sd);
				if side ~= nil and side:IsWater() and side:GetY() == best:GetY() and side:GetFeatureType() ~= FeatureTypes.FEATURE_ICE then
					if MurkIceColumnOk(side:GetX(), skip, iW, mirrored) then
						side:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
						break
					end
				end
				sd = sd + 1;
			end
		end
		plot = best;
		steps = steps + 1;
	end
end
------------------------------------------------------------------------------
function AddNorthIceArms()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local iceFrac = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
	local iceCut = iceFrac:GetHeight(62);
	local northY = iH - 1;
	local iceSeeds = {};
	local x = 0;
	while x < iW do
		if MurkIceColumnOk(x, skip, iW, mirrored) then
			local plot = Map.GetPlot(x, northY);
			if plot ~= nil and plot:IsWater() and iceFrac:GetHeight(x, northY) >= iceCut then
				plot:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
				table.insert(iceSeeds, plot);
			end
		end
		x = x + 1;
	end
	local si = 1;
	while si <= #iceSeeds do
		GrowMurkIceArm(iceSeeds[si], iH, skip, iW, mirrored);
		si = si + 1;
	end
end
------------------------------------------------------------------------------
function CountMireMountainNeighbors(plot)
	local n = 0;
	if plot == nil then
		return n
	end
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			n = n + 1;
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function BreakMireTundraMountainPairs(iW, iH, skip)
	local seen = {};
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if seen[i] ~= true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					local comp = {};
					local q = {plot};
					seen[i] = true;
					table.insert(comp, plot);
					local hasTundra = (mireBand[i] == 1);
					local qi = 1;
					while qi <= #q do
						local p = q[qi];
						qi = qi + 1;
						local d = 0;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
							if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
								local ai = adj:GetY() * iW + adj:GetX() + 1;
								if seen[ai] ~= true then
									seen[ai] = true;
									table.insert(q, adj);
									table.insert(comp, adj);
									if mireBand[ai] == 1 then
										hasTundra = true;
									end
								end
							end
							d = d + 1;
						end
					end
					if hasTundra and #comp == 2 then
						local a = comp[1];
						local b = comp[2];
						local aFront = MireIsFrontRidgeX(a:GetX(), iW);
						local bFront = MireIsFrontRidgeX(b:GetX(), iW);
						local drop = a;
						if aFront ~= bFront then
							if aFront then
								drop = b;
							else
								drop = a;
							end
						else
							local d0 = mireBand[a:GetY() * iW + a:GetX() + 1];
							local d1 = mireBand[b:GetY() * iW + b:GetX() + 1];
							if d0 == 1 and d1 ~= 1 then
								drop = a;
							elseif d1 == 1 and d0 ~= 1 then
								drop = b;
							else
								drop = comp[1 + Map.Rand(2, "Mire Spike Break Pair")];
							end
						end
						drop:SetPlotType(PlotTypes.PLOT_LAND, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Mire tundra mountain pairs broken:", n);
end
------------------------------------------------------------------------------
function SlashMireMountainBlobs(iW, iH, skip)
	local mirrored = (DEF_MIRRORED == 1);
	local nCut = 0;
	local pass = 1;
	while pass <= 4 do
		local seen = {};
		local nThis = 0;
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				local i = y * iW + x + 1;
				if seen[i] ~= true and skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						local comp = {};
						local q = {plot};
						seen[i] = true;
						table.insert(comp, plot);
						local qi = 1;
						while qi <= #q do
							local p = q[qi];
							qi = qi + 1;
							local d = 0;
							while d < DirectionTypes.NUM_DIRECTION_TYPES do
								local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
								if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
									local ax = adj:GetX();
									local ai = adj:GetY() * iW + ax + 1;
									if seen[ai] ~= true and skip[ax] ~= true and MirrorOwnsPlot(ax, adj:GetY(), mirrored, iW) then
										seen[ai] = true;
										table.insert(q, adj);
										table.insert(comp, adj);
									end
								end
								d = d + 1;
							end
						end
						if #comp >= 7 then
							local sx = 0;
							local sy = 0;
							local bi = 1;
							while bi <= #comp do
								sx = sx + comp[bi]:GetX();
								sy = sy + comp[bi]:GetY();
								bi = bi + 1;
							end
							local cx = sx / #comp;
							local cy = sy / #comp;
							local scored = {};
							bi = 1;
							while bi <= #comp do
								local dx = comp[bi]:GetX() - cx;
								local dy = comp[bi]:GetY() - cy;
								table.insert(scored, {comp[bi], dx * dx + dy * dy});
								bi = bi + 1;
							end
							table.sort(scored, function(a, b)
								return a[2] < b[2]
							end);
							local want = 2 + Map.Rand(2, "Mire Mtn Slash");
							local k = 1;
							while k <= #scored and want > 0 do
								local drop = scored[k][1];
								if drop:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
									drop:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
									want = want - 1;
									nCut = nCut + 1;
									nThis = nThis + 1;
								end
								k = k + 1;
							end
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if nThis == 0 then
			break
		end
		pass = pass + 1;
	end
	print("Mire mountain slash tiles:", nCut);
end
------------------------------------------------------------------------------
function ThinMireDenseForest(iW, iH, skip)
	local mirrored = (DEF_MIRRORED == 1);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if mireBand[i] == 2 and skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
					local neigh = CountFeatureNeighbors(plot, FeatureTypes.FEATURE_FOREST);
					local chance = 0;
					if neigh >= 6 then
						chance = 30;
					elseif neigh >= 5 then
						chance = 15;
					end
					if chance > 0 and Map.Rand(100, "Mire Dense Forest Thin") < chance then
						plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Mire dense forest thinned:", n);
end
------------------------------------------------------------------------------
function CarveMireCorridorPlot(plot)
	if plot == nil or plot:IsWater() then
		return
	end
	if plot:GetPlotType() ~= PlotTypes.PLOT_LAND then
		plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
	end
	plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
end
------------------------------------------------------------------------------
function StepMireCorridor(x, y, tx, ty, skip, wantBand, iW)
	local best = nil;
	local bestScore = -99999;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil then
			local ax = adj:GetX();
			local ay = adj:GetY();
			if skip[ax] ~= true and adj:IsWater() == false then
				local dist = Map.PlotDistance(ax, ay, tx, ty);
				local score = 0 - dist;
				local bi = ay * iW + ax + 1;
				if mireBand[bi] == wantBand then
					score = score + 4;
				end
				if adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					score = score + 1;
				end
				if score > bestScore or (score == bestScore and Map.Rand(2, "Mire Corridor Tie") == 0) then
					bestScore = score;
					best = adj;
				end
			end
		end
		d = d + 1;
	end
	return best;
end
------------------------------------------------------------------------------
function WalkMireCorridor(sx, sy, tx, ty, skip, wantBand, iW, maxSteps)
	local plot = Map.GetPlot(sx, sy);
	local seen = {};
	local steps = 0;
	while plot ~= nil and steps < maxSteps do
		local idx = plot:GetY() * iW + plot:GetX() + 1;
		if seen[idx] == true then
			break
		end
		seen[idx] = true;
		CarveMireCorridorPlot(plot);
		if plot:GetX() == tx and plot:GetY() == ty then
			break
		end
		local nxt = StepMireCorridor(plot:GetX(), plot:GetY(), tx, ty, skip, wantBand, iW);
		if nxt == nil then
			break
		end
		plot = nxt;
		steps = steps + 1;
	end
end
------------------------------------------------------------------------------
function PickMirePlotNear(plots, tx, ty, maxDist)
	local best = nil;
	local bestD = 9999;
	local i = 1;
	while i <= #plots do
		local p = plots[i];
		local d = Map.PlotDistance(p:GetX(), p:GetY(), tx, ty);
		if d < bestD or (d == bestD and Map.Rand(2, "Mire Pick Near") == 0) then
			bestD = d;
			best = p;
		end
		i = i + 1;
	end
	if best ~= nil and maxDist ~= nil and bestD > maxDist then
		return nil
	end
	return best;
end
------------------------------------------------------------------------------
function MireIsFrontRidgeX(x, iW)
	if x == nil or iW == nil then
		return false
	end
	local mid = math.floor(iW / 2);
	local xCenter = mid - 4;
	local xMin = xCenter - 2;
	local xMax = xCenter + 2;
	if xMin < 0 then
		xMin = 0;
	end
	if xMax >= mid then
		xMax = mid - 1;
	end
	if x >= xMin and x <= xMax then
		return true
	end
	if IsSnowWrapX() then
		local xw = GetSnowWrapLandMountainXs(iW);
		if x >= xw - 2 and x <= xw + 2 then
			return true
		end
	end
	return false
end
------------------------------------------------------------------------------
function MireApplyBandTerrain(plot, band)
	if plot == nil or plot:IsWater() then
		return
	end
	local keepMtn = MireIsFrontRidgeX(plot:GetX(), Map.GetGridSize());
	if band == 1 then
		if keepMtn == false and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		end
		plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
	elseif band == 2 then
		if keepMtn == false and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		end
		if Map.Rand(100, "Mire Wood Plains") < 28 then
			plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
		else
			plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
		end
	else
		if keepMtn == false then
			if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
				plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			end
			if plot:GetPlotType() == PlotTypes.PLOT_HILLS and Map.Rand(100, "Mire Fen Hill Keep") >= 12 then
				plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
			end
		end
		plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
	end
end
------------------------------------------------------------------------------
function MireBleedFenWood(iW, iH, skip, mirrored)
	local pass = 1;
	while pass <= 1 do
		local toWood = {};
		local toFen = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local i = y * iW + x + 1;
					local band = mireBand[i];
					if band == 2 or band == 3 then
						local d = 0;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(x, y, d);
							if adj ~= nil and adj:IsWater() == false then
								local ax = adj:GetX();
								local ay = adj:GetY();
								if skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
									local ai = ay * iW + ax + 1;
									local ab = mireBand[ai];
									if band == 2 and ab == 3 and ay <= y then
										if Map.Rand(100, "Mire Wood South") < 34 then
											toWood[ai] = adj;
										end
									elseif band == 3 and ab == 2 and ay >= y then
										if Map.Rand(100, "Mire Fen North") < 22 then
											toFen[ai] = adj;
										end
									end
								end
							end
							d = d + 1;
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local i, plot;
		for i, plot in pairs(toWood) do
			if toFen[i] == nil and mireBand[i] == 3 then
				mireBand[i] = 2;
				MireApplyBandTerrain(plot, 2);
			end
		end
		for i, plot in pairs(toFen) do
			if toWood[i] == nil and mireBand[i] == 2 then
				mireBand[i] = 3;
				MireApplyBandTerrain(plot, 3);
			end
		end
		pass = pass + 1;
	end
end
------------------------------------------------------------------------------
function MireCountBandNeighbors(x, y, band, iW)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(x, y, d);
		if adj ~= nil then
			local ai = adj:GetY() * iW + adj:GetX() + 1;
			if mireBand[ai] == band then
				n = n + 1;
			end
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function MireBleedTundraWood(iW, iH, skip, mirrored)
	local pass = 1;
	while pass <= 2 do
		local toTundra = {};
		local toWood = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local i = y * iW + x + 1;
					local band = mireBand[i];
					if (band == 1 or band == 2) and MireCountBandNeighbors(x, y, band, iW) >= 2 then
						local d = 0;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(x, y, d);
							if adj ~= nil and adj:IsWater() == false then
								local ax = adj:GetX();
								local ay = adj:GetY();
								if skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
									local ai = ay * iW + ax + 1;
									local ab = mireBand[ai];
									if band == 1 and ab == 2 and ay <= y then
										if Map.Rand(100, "Mire Tundra South") < 38 then
											toTundra[ai] = adj;
										end
									elseif band == 2 and ab == 1 and ay >= y then
										if Map.Rand(100, "Mire Wood North") < 28 then
											toWood[ai] = adj;
										end
									end
								end
							end
							d = d + 1;
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		local idx, plot;
		for idx, plot in pairs(toTundra) do
			if toWood[idx] == nil and mireBand[idx] == 2 then
				mireBand[idx] = 1;
				MireApplyBandTerrain(plot, 1);
			end
		end
		for idx, plot in pairs(toWood) do
			if toTundra[idx] == nil and mireBand[idx] == 1 then
				mireBand[idx] = 2;
				MireApplyBandTerrain(plot, 2);
			end
		end
		pass = pass + 1;
	end
end
------------------------------------------------------------------------------
-- Flood-fills each same-band component and, if it's small (<=2 tiles),
-- flips it to whichever OTHER band actually borders it most -- not a fixed
-- 1<->2 swap, so a stray tundra speck surrounded by marsh becomes marsh
-- (not forest), a stray grass/plains speck surrounded by tundra becomes
-- tundra, etc. Covers all 3 bands (tundra/wood/fen), not just 1 and 2, so
-- isolated marsh specks get cleaned up the same way.
function MireCullSmallBandPatches(iW, iH, skip, mirrored)
	local seen = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if seen[i] ~= true and skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local band = mireBand[i];
				if band == 1 or band == 2 or band == 3 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false then
						local comp = {};
						local q = {plot};
						seen[i] = true;
						table.insert(comp, plot);
						local borderCount = {0, 0, 0};
						local qi = 1;
						while qi <= #q do
							local p = q[qi];
							qi = qi + 1;
							local d = 0;
							while d < DirectionTypes.NUM_DIRECTION_TYPES do
								local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
								if adj ~= nil then
									local ax = adj:GetX();
									local ai = adj:GetY() * iW + ax + 1;
									local aBand = mireBand[ai];
									if aBand == band and seen[ai] ~= true and skip[ax] ~= true and adj:IsWater() == false then
										seen[ai] = true;
										table.insert(q, adj);
										table.insert(comp, adj);
									elseif aBand ~= band and aBand ~= nil and aBand >= 1 and aBand <= 3 and skip[ax] ~= true and adj:IsWater() == false then
										borderCount[aBand] = borderCount[aBand] + 1;
									end
								end
								d = d + 1;
							end
						end
						if #comp <= 2 then
							local flip = band;
							local best = 0;
							local bi = 1;
							while bi <= 3 do
								if bi ~= band and borderCount[bi] > best then
									best = borderCount[bi];
									flip = bi;
								end
								bi = bi + 1;
							end
							if flip ~= band then
								local ci = 1;
								while ci <= #comp do
									local p = comp[ci];
									local pi = p:GetY() * iW + p:GetX() + 1;
									mireBand[pi] = flip;
									MireApplyBandTerrain(p, flip);
									ci = ci + 1;
								end
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function PlaceMireFenLakes(iW, iH, skip, mirrored)
	local fenLake = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if mireBand[i] == 3 and skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:IsCoastalLand() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and WaterAllowedAtX(x) then
					table.insert(fenLake, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local lakeWant = 4;
	if iH >= 32 then
		lakeWant = 6;
	end
	local lakes = 0;
	while lakes < lakeWant and #fenLake > 0 do
		local idx = 1 + Map.Rand(#fenLake, "Mire Fen Lake");
		local plot = fenLake[idx];
		table.remove(fenLake, idx);
		if plot:IsWater() == false and plot:IsCoastalLand() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
			plot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
			plot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
			plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			lakes = lakes + 1;
			if Map.Rand(100, "Mire Fen Lake Grow") < 40 then
				local d = Map.Rand(DirectionTypes.NUM_DIRECTION_TYPES, "Mire Fen Lake Dir");
				local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
				if adj ~= nil then
					local ai = adj:GetY() * iW + adj:GetX() + 1;
					if mireBand[ai] == 3 and adj:IsWater() == false and adj:IsCoastalLand() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and skip[adj:GetX()] ~= true then
						adj:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
						adj:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
						adj:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
					end
				end
			end
		end
	end
	print("Mire fen lakes:", lakes);
	if lakes > 0 then
		Map.CalculateAreas();
	end
end
------------------------------------------------------------------------------
function PlaceMireWoodBlobs(iW, iH, skip, mirrored)
	local roll = Map.Rand(100, "Mire Wood Blob Count");
	local nBlobs = 0;
	if roll < 28 then
		nBlobs = 0;
	elseif roll < 62 then
		nBlobs = 1;
	elseif roll < 96 then
		nBlobs = 2;
	else
		nBlobs = 3;
	end
	local needNeigh = 4;
	local b = 0;
	while b < nBlobs do
		local cands = {};
		local weights = {};
		local total = 0;
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) and MireIsFrontRidgeX(x, iW) == false then
					local i = y * iW + x + 1;
					if mireBand[i] == 2 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and CountMireMountainNeighbors(plot) == 0 then
							local neigh = CountFeatureNeighbors(plot, FeatureTypes.FEATURE_FOREST);
							if plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
								neigh = neigh + 1;
							end
							if neigh >= needNeigh then
								local w = neigh * neigh;
								if y < iH * 0.52 then
									w = w * 3;
								elseif y < iH * 0.62 then
									w = w * 2;
								end
								table.insert(cands, plot);
								table.insert(weights, w);
								total = total + w;
							end
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if total < 1 then
			if needNeigh > 2 then
				needNeigh = needNeigh - 1;
			else
				break
			end
		else
			local pick = Map.Rand(total, "Mire Wood Blob Seed");
			local seed = cands[1];
			local ci = 1;
			while ci <= #cands do
				if pick < weights[ci] then
					seed = cands[ci];
					break
				end
				pick = pick - weights[ci];
				ci = ci + 1;
			end
			local q = {seed};
			seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
			seed:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			local grown = 1;
			local target = 4 + Map.Rand(5, "Mire Wood Blob Size");
			local qi = 1;
			while qi <= #q and grown < target do
				local p = q[qi];
				qi = qi + 1;
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
					if adj ~= nil and grown < target then
						local ax = adj:GetX();
						local ai = adj:GetY() * iW + ax + 1;
						if skip[ax] ~= true and MireIsFrontRidgeX(ax, iW) == false and mireBand[ai] == 2 and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							if Map.Rand(100, "Mire Wood Blob Grow") < 70 then
								adj:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
								adj:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
								table.insert(q, adj);
								grown = grown + 1;
							end
						end
					end
					d = d + 1;
				end
			end
			b = b + 1;
		end
	end
	print("Mire wood blobs:", nBlobs);
end
------------------------------------------------------------------------------
function PlaceMirePlainsClearings(iW, iH, skip, mirrored)
	local nClear = 1;
	if Map.Rand(100, "Mire Clearing Count") < 55 then
		nClear = 2;
	end
	local c = 0;
	local nTiles = 0;
	local needNeigh = 4;
	while c < nClear do
		local cands = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) and MireIsFrontRidgeX(x, iW) == false then
					local i = y * iW + x + 1;
					if mireBand[i] == 2 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and CountMireMountainNeighbors(plot) == 0 then
							if plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
								local neigh = CountFeatureNeighbors(plot, FeatureTypes.FEATURE_FOREST);
								if neigh >= needNeigh then
									table.insert(cands, plot);
								end
							end
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands < 1 then
			if needNeigh > 2 then
				needNeigh = needNeigh - 1;
			else
				break
			end
		else
			local seed = cands[1 + Map.Rand(#cands, "Mire Clearing Seed")];
			local q = {seed};
			local grown = 1;
			local target = 5 + Map.Rand(5, "Mire Clearing Size");
			local qi = 1;
			while qi <= #q and grown < target do
				local p = q[qi];
				qi = qi + 1;
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
					if adj ~= nil and grown < target then
						local ax = adj:GetX();
						local ai = adj:GetY() * iW + ax + 1;
						if skip[ax] ~= true and MireIsFrontRidgeX(ax, iW) == false and mireBand[ai] == 2 and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							if adj:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
								if Map.Rand(100, "Mire Clearing Grow") < 78 then
									table.insert(q, adj);
									grown = grown + 1;
								end
							end
						end
					end
					d = d + 1;
				end
			end
			local ti = 1;
			while ti <= #q do
				local plot = q[ti];
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
				if Map.Rand(100, "Mire Clearing Plains") < 86 then
					plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
				else
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
				end
				if plot:GetPlotType() == PlotTypes.PLOT_LAND and Map.Rand(100, "Mire Clearing Hill") < 36 then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				end
				nTiles = nTiles + 1;
				ti = ti + 1;
			end
			c = c + 1;
		end
	end
	print("Mire plains clearings:", c, " tiles:", nTiles);
end
------------------------------------------------------------------------------
function AddMireBands()
	mireBand = {};
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local frac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	local fracFen = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
	local hLo = frac:GetHeight(10);
	local hHi = frac:GetHeight(90);
	local fLo = fracFen:GetHeight(8);
	local fHi = fracFen:GetHeight(92);
	local nSpike = 0;
	local nWood = 0;
	local nFen = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			mireBand[i] = 0;
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local yNorm = 0;
					if iH > 1 then
						yNorm = y / (iH - 1);
					end
					local jitter = 0;
					if hHi > hLo then
						jitter = ((frac:GetHeight(x, y) - hLo) / (hHi - hLo) - 0.5) * 0.36;
					end
					local fenJitter = 0;
					if fHi > fLo then
						fenJitter = ((fracFen:GetHeight(x, y) - fLo) / (fHi - fLo) - 0.5) * 0.38;
					end
					local band = 1;
					if yNorm + jitter < 0.703 then
						if yNorm + fenJitter < 0.32 then
							band = 3;
						else
							band = 2;
						end
					end
					mireBand[i] = band;
					MireApplyBandTerrain(plot, band);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	MireBleedFenWood(iW, iH, skip, mirrored);
	MireBleedTundraWood(iW, iH, skip, mirrored);
	MireCullSmallBandPatches(iW, iH, skip, mirrored);
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			local band = mireBand[i];
			if band == 1 then
				nSpike = nSpike + 1;
			elseif band == 2 then
				nWood = nWood + 1;
			elseif band == 3 then
				nFen = nFen + 1;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if mireBand[i] == 1 and MireIsFrontRidgeX(x, iW) == false then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if CountMireMountainNeighbors(plot) == 0 and Map.Rand(100, "Mire Spike Peak") < 14 then
						plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local spikeLand = {};
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if mireBand[i] == 1 and skip[x] ~= true and MireIsFrontRidgeX(x, iW) == false then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					table.insert(spikeLand, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nRare = 0;
	if Map.Rand(100, "Mire Tundra Rare Blob") < 18 then
		nRare = 1;
	end
	if Map.Rand(100, "Mire Tundra Rare Blob2") < 5 then
		nRare = nRare + 1;
	end
	local rb = 0;
	while rb < nRare and #spikeLand > 6 do
		local seed = spikeLand[1 + Map.Rand(#spikeLand, "Mire Tundra Blob Seed")];
		if seed:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and CountMireMountainNeighbors(seed) == 0 then
			local q = {seed};
			seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
			local grown = 1;
			local target = 3 + Map.Rand(3, "Mire Tundra Blob Size");
			local qi = 1;
			while qi <= #q and grown < target do
				local p = q[qi];
				qi = qi + 1;
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
					if adj ~= nil and grown < target then
						local ax = adj:GetX();
						local ai = adj:GetY() * iW + ax + 1;
						if skip[ax] ~= true and MireIsFrontRidgeX(ax, iW) == false and mireBand[ai] == 1 and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							if Map.Rand(100, "Mire Tundra Blob Grow") < 62 then
								adj:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
								table.insert(q, adj);
								grown = grown + 1;
							end
						end
					end
					d = d + 1;
				end
			end
			if grown < 3 then
				local fi = 2;
				while fi <= #q do
					q[fi]:SetPlotType(PlotTypes.PLOT_LAND, false, false);
					fi = fi + 1;
				end
			end
		end
		rb = rb + 1;
	end
	BreakMireTundraMountainPairs(iW, iH, skip);
	local snowFrac = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
	local snowCut = {};
	snowCut[0] = snowFrac:GetHeight(64);
	snowCut[1] = snowFrac:GetHeight(78);
	snowCut[2] = snowFrac:GetHeight(88);
	snowCut[3] = snowFrac:GetHeight(96);
	local snowY = iH - 4;
	if snowY < 0 then
		snowY = 0;
	end
	while snowY < iH do
		local fromNorth = iH - 1 - snowY;
		local cut = snowCut[fromNorth];
		if cut == nil then
			cut = snowCut[3];
		end
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, snowY);
				if plot ~= nil and plot:IsWater() == false and snowFrac:GetHeight(x, snowY) >= cut then
					plot:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
				end
			end
			x = x + 1;
		end
		snowY = snowY + 1;
	end
	snowY = iH - 4;
	if snowY < 0 then
		snowY = 0;
	end
	while snowY < iH do
		local fromNorth = iH - 1 - snowY;
		local growChance = 58 - fromNorth * 14;
		if growChance < 12 then
			growChance = 12;
		end
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, snowY);
				if plot ~= nil and plot:IsWater() == false and plot:GetTerrainType() ~= TerrainTypes.TERRAIN_SNOW then
					if CountAdjacentTerrain(plot, TerrainTypes.TERRAIN_SNOW) >= 1 and Map.Rand(100, "Mire Snow Grow") < growChance then
						plot:SetTerrainType(TerrainTypes.TERRAIN_SNOW, false, false);
					end
				end
			end
			x = x + 1;
		end
		snowY = snowY + 1;
	end
	local hillFrac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	local hillCut = {};
	hillCut[0] = hillFrac:GetHeight(78);
	hillCut[1] = hillFrac:GetHeight(90);
	hillCut[2] = hillFrac:GetHeight(96);
	local hillY = 0;
	while hillY <= 2 and hillY < iH do
		local cut = hillCut[hillY];
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, hillY, mirrored, iW) then
				local plot = Map.GetPlot(x, hillY);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND and hillFrac:GetHeight(x, hillY) >= cut then
					plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				end
			end
			x = x + 1;
		end
		hillY = hillY + 1;
	end
	hillY = 0;
	while hillY <= 2 and hillY < iH do
		local growChance = 58 - hillY * 19;
		if growChance < 12 then
			growChance = 12;
		end
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, hillY, mirrored, iW) then
				local plot = Map.GetPlot(x, hillY);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND then
					local hn = 0;
					local d = 0;
					while d < DirectionTypes.NUM_DIRECTION_TYPES do
						local adj = PlotDirNoXWrap(x, hillY, d);
						if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_HILLS then
							hn = hn + 1;
						end
						d = d + 1;
					end
					if hn >= 1 and Map.Rand(100, "Mire South Hill Grow") < growChance then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
					end
				end
			end
			x = x + 1;
		end
		hillY = hillY + 1;
	end
	local coastFlats = {};
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND and plot:IsCoastalLand() then
					local westWater = false;
					local d = 0;
					while d < DirectionTypes.NUM_DIRECTION_TYPES do
						local adj = PlotDirNoXWrap(x, y, d);
						if adj ~= nil and adj:IsWater() and adj:IsLake() == false and adj:GetX() <= x then
							westWater = true;
							break
						end
						d = d + 1;
					end
					if westWater then
						table.insert(coastFlats, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nCoastHill = 0;
	local ci = 1;
	while ci <= #coastFlats do
		if Map.Rand(100, "Mire Back Coast Hill") < 22 then
			coastFlats[ci]:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			nCoastHill = nCoastHill + 1;
		end
		ci = ci + 1;
	end
	ci = 1;
	while ci <= #coastFlats do
		local plot = coastFlats[ci];
		if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
				if adj ~= nil and adj:IsWater() == false and adj:GetPlotType() == PlotTypes.PLOT_LAND and skip[adj:GetX()] ~= true then
					if Map.Rand(100, "Mire Back Coast Hill Grow") < 28 then
						adj:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						nCoastHill = nCoastHill + 1;
					end
				end
				d = d + 1;
			end
		end
		ci = ci + 1;
	end
	PlaceMireFenLakes(iW, iH, skip, mirrored);
	print("Mire bands spike:", nSpike, " wood:", nWood, " fen:", nFen, " backHills:", nCoastHill);
end
------------------------------------------------------------------------------
function AddMireFeatures()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local spikePlots = {};
	local fenMarsh = {};
	local fenForest = {};
	local woodWest = {};
	local woodEast = {};
	local woodSouth = {};
	local woodNorth = {};
	local minX, maxX = GetSnowWrapWaterBounds(iW);
	if minX > maxX then
		minX = 2;
		maxX = math.floor(iW / 2) - 2;
	end
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			local band = mireBand[i];
			if band ~= nil and band > 0 and skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local feat = plot:GetFeatureType();
					if feat == FeatureTypes.FEATURE_JUNGLE or feat == FeatureTypes.FEATURE_MARSH or feat == FeatureTypes.FEATURE_FLOOD_PLAINS or feat == FeatureTypes.FEATURE_OASIS then
						plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
					end
					if plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if band == 1 then
							table.insert(spikePlots, plot);
							-- Small icy ponds scattered through the tundra band
							-- itself (not just the back-coast edge) -- was a
							-- ~1% chance across only the outermost 3 rows,
							-- easy to never see in practice; widened to a
							-- 5-row band at a more noticeable ~5% chance.
							if y >= iH - 5 and WaterAllowedAtX(x) and plot:IsCoastalLand() == false and Map.Rand(20, "Mire Ice Pond") == 0 then
								plot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
								plot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
								plot:SetFeatureType(FeatureTypes.FEATURE_ICE, -1);
							end
						elseif band == 2 then
							if plot:GetPlotType() ~= PlotTypes.PLOT_OCEAN then
								if Map.Rand(100, "Mire Wood Forest") < 92 then
									plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
								end
								if x >= minX and x <= maxX then
									if x <= minX + 2 then
										table.insert(woodWest, plot);
									end
									if x >= maxX - 2 then
										table.insert(woodEast, plot);
									end
									if y < iH * 0.45 then
										table.insert(woodSouth, plot);
									end
									if y > iH * 0.55 then
										table.insert(woodNorth, plot);
									end
								end
							end
						else
							if plot:GetPlotType() == PlotTypes.PLOT_LAND and plot:GetTerrainType() == TerrainTypes.TERRAIN_GRASS then
								table.insert(fenMarsh, plot);
							end
							table.insert(fenForest, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local pinePlots = {};
	local pi = 1;
	while pi <= #spikePlots do
		if spikePlots[pi]:IsWater() == false and spikePlots[pi]:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and spikePlots[pi]:GetFeatureType() == FeatureTypes.NO_FEATURE and spikePlots[pi]:GetTerrainType() ~= TerrainTypes.TERRAIN_SNOW then
			table.insert(pinePlots, spikePlots[pi]);
		end
		pi = pi + 1;
	end
	local pineN, pineT = PlaceClusteredFeature(pinePlots, FeatureTypes.FEATURE_FOREST, 20, "Mire Spike Pine");
	local nEW = 2;
	if iH >= 36 then
		nEW = 3;
	end
	local ei = 0;
	while ei < nEW do
		if #woodWest > 0 and #woodEast > 0 then
			local a = woodWest[1 + Map.Rand(#woodWest, "Mire EW West")];
			local b = woodEast[1 + Map.Rand(#woodEast, "Mire EW East")];
			WalkMireCorridor(a:GetX(), a:GetY(), b:GetX(), b:GetY(), skip, 2, iW, iW + iH);
		end
		ei = ei + 1;
	end
	local nNS = 2;
	if iW >= 56 then
		nNS = 3;
	end
	local ni = 0;
	while ni < nNS do
		local tx = minX + math.floor((maxX - minX) * (ni + 1) / (nNS + 1));
		local south = PickMirePlotNear(woodSouth, tx, math.floor(iH * 0.38), nil);
		local north = PickMirePlotNear(woodNorth, tx, math.floor(iH * 0.62), nil);
		if south ~= nil and north ~= nil then
			WalkMireCorridor(south:GetX(), south:GetY(), north:GetX(), north:GetY(), skip, 2, iW, iW + iH);
		end
		ni = ni + 1;
	end
	if mirrored == false then
		local emin = iW - 1 - maxX;
		local emax = iW - 1 - minX;
		if emin > emax then
			local tmp = emin;
			emin = emax;
			emax = tmp;
		end
		local eWest = {};
		local eEast = {};
		local eSouth = {};
		local eNorth = {};
		y = 0;
		while y < iH do
			local x = emin;
			while x <= emax do
				local i = y * iW + x + 1;
				if mireBand[i] == 2 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if x <= emin + 2 then
							table.insert(eWest, plot);
						end
						if x >= emax - 2 then
							table.insert(eEast, plot);
						end
						if y < iH * 0.45 then
							table.insert(eSouth, plot);
						end
						if y > iH * 0.55 then
							table.insert(eNorth, plot);
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		ei = 0;
		while ei < nEW do
			if #eWest > 0 and #eEast > 0 then
				local a = eWest[1 + Map.Rand(#eWest, "Mire EEW West")];
				local b = eEast[1 + Map.Rand(#eEast, "Mire EEW East")];
				WalkMireCorridor(a:GetX(), a:GetY(), b:GetX(), b:GetY(), skip, 2, iW, iW + iH);
			end
			ei = ei + 1;
		end
		ni = 0;
		while ni < nNS do
			local tx = emin + math.floor((emax - emin) * (ni + 1) / (nNS + 1));
			local south = PickMirePlotNear(eSouth, tx, math.floor(iH * 0.38), nil);
			local north = PickMirePlotNear(eNorth, tx, math.floor(iH * 0.62), nil);
			if south ~= nil and north ~= nil then
				WalkMireCorridor(south:GetX(), south:GetY(), north:GetX(), north:GetY(), skip, 2, iW, iW + iH);
			end
			ni = ni + 1;
		end
	end
	PlaceMireWoodBlobs(iW, iH, skip, mirrored);
	PlaceMirePlainsClearings(iW, iH, skip, mirrored);
	local marshLeft = {};
	local mi = 1;
	while mi <= #fenMarsh do
		if fenMarsh[mi]:IsWater() == false and fenMarsh[mi]:GetPlotType() == PlotTypes.PLOT_LAND and fenMarsh[mi]:GetTerrainType() == TerrainTypes.TERRAIN_GRASS and fenMarsh[mi]:GetFeatureType() == FeatureTypes.NO_FEATURE then
			table.insert(marshLeft, fenMarsh[mi]);
		end
		mi = mi + 1;
	end
	local marshN, marshT = PlaceClusteredFeature(marshLeft, FeatureTypes.FEATURE_MARSH, 42, "Mire Fen Marsh");
	local forestLeft = {};
	local fi = 1;
	while fi <= #fenForest do
		if fenForest[fi]:IsWater() == false and fenForest[fi]:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and fenForest[fi]:GetFeatureType() == FeatureTypes.NO_FEATURE then
			table.insert(forestLeft, fenForest[fi]);
		end
		fi = fi + 1;
	end
	local fenForN, fenForT = PlaceClusteredFeature(forestLeft, FeatureTypes.FEATURE_FOREST, 15, "Mire Fen Forest");
	BreakMireTundraMountainPairs(iW, iH, skip);
	SlashMireMountainBlobs(iW, iH, skip);
	BreakMireTundraMountainPairs(iW, iH, skip);
	ThinMireDenseForest(iW, iH, skip);
	print("Mire pines:", pineN, "/", pineT, " marsh:", marshN, "/", marshT, " fen forest:", fenForN, "/", fenForT);
end
------------------------------------------------------------------------------
local wastelandWaterDist = {};
function AddWastelandWaterLayout()
	wastelandWaterDist = {};
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local tundraCols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #tundraCols do
		skip[tundraCols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local INF = 99;
	local dist = {};
	local qx = {};
	local qy = {};
	local qn = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			dist[i] = INF;
			if ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and PlotIsWastelandWaterSource(plot) then
					dist[i] = 0;
					qn = qn + 1;
					qx[qn] = x;
					qy[qn] = y;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local qi = 1;
	while qi <= qn do
		local cx = qx[qi];
		local cy = qy[qi];
		local cd = dist[cy * iW + cx + 1];
		qi = qi + 1;
		local ddir = 0;
		while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(cx, cy, ddir);
			if adj ~= nil then
				local ax = adj:GetX();
				local ay = adj:GetY();
				if ((not mirrored) or (ax <= iW * 0.5)) then
					local ai = ay * iW + ax + 1;
					if dist[ai] > cd + 1 then
						dist[ai] = cd + 1;
						qn = qn + 1;
						qx[qn] = ax;
						qy[qn] = ay;
					end
				end
			end
			ddir = ddir + 1;
		end
	end
	local maxDist = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					local i = y * iW + x + 1;
					if dist[i] < INF and dist[i] > maxDist then
						maxDist = dist[i];
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local desertCut = maxDist - 3;
	if desertCut < 5 then
		desertCut = 5;
	end
	local rimFrac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	local rimH3 = rimFrac:GetHeight(95);
	local rimH1 = rimFrac:GetHeight(80);
	local nFertile = 0;
	local nDesert = 0;
	local nwFeat = {};
	for row in GameInfo.Features() do
		if row.NaturalWonder then
			nwFeat[row.ID] = true;
		end
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			wastelandWaterDist[i] = dist[i];
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					local d = dist[i];
					local feat = plot:GetFeatureType();
					if nwFeat[feat] ~= true then
					local rh = rimFrac:GetHeight(x, y);
					local rimW = 2;
					if rh >= rimH3 then
						rimW = 3;
					elseif rh >= rimH1 then
						rimW = 1;
					end
					if d <= rimW then
						if d <= 1 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
						elseif Map.Rand(100, "Wasteland Rim Plains") < 35 then
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						else
							plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
						end
						nFertile = nFertile + 1;
					elseif maxDist >= 5 and d >= desertCut then
						local nearSep = false;
						local si = 1;
						while si <= #tundraCols do
							local dx = x - tundraCols[si];
							if dx < 0 then
								dx = 0 - dx;
							end
							if dx < 3 then
								nearSep = true;
								break
							end
							si = si + 1;
						end
						if nearSep then
							plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
						else
							plot:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
							nDesert = nDesert + 1;
						end
					else
						plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
					end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	JagWastelandBigDeserts(iW, iH, skip, mirrored);
	BufferWastelandDesertFromLush(iW, iH, skip, mirrored);
	CullWastelandDesertSpeckles(iW, iH, skip, mirrored);
	print("Wasteland water layout fertile:", nFertile, " desert:", nDesert, " maxDist:", maxDist);
end
------------------------------------------------------------------------------
function BufferWastelandDesertFromLush(iW, iH, skip, mirrored)
	local hit = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					local lush = false;
					local d = 0;
					while d < DirectionTypes.NUM_DIRECTION_TYPES do
						local adj = PlotDirNoXWrap(x, y, d);
						if adj ~= nil then
							local t = adj:GetTerrainType();
							if t == TerrainTypes.TERRAIN_GRASS or t == TerrainTypes.TERRAIN_PLAINS then
								lush = true;
								break
							end
						end
						d = d + 1;
					end
					if lush then
						table.insert(hit, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local i = 1;
	while i <= #hit do
		hit[i]:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function CullWastelandDesertSpeckles(iW, iH, skip, mirrored)
	local seen = {};
	local y0 = 0;
	while y0 < iH do
		local x0 = 0;
		while x0 < iW do
			local i0 = y0 * iW + x0 + 1;
			if seen[i0] ~= true and skip[x0] ~= true and ((not mirrored) or (x0 <= iW * 0.5)) then
				local seed = Map.GetPlot(x0, y0);
				if seed ~= nil and seed:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					local comp = {};
					local qx = {x0};
					local qy = {y0};
					seen[i0] = true;
					table.insert(comp, seed);
					local qi = 1;
					while qi <= #qx do
						local cx = qx[qi];
						local cy = qy[qi];
						qi = qi + 1;
						local ddir = 0;
						while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(cx, cy, ddir);
							if adj ~= nil then
								local ax = adj:GetX();
								local ay = adj:GetY();
								local ai = ay * iW + ax + 1;
								if seen[ai] ~= true and skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
									if adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
										seen[ai] = true;
										table.insert(comp, adj);
										table.insert(qx, ax);
										table.insert(qy, ay);
									end
								end
							end
							ddir = ddir + 1;
						end
					end
					if #comp < 5 then
						local ci = 1;
						while ci <= #comp do
							comp[ci]:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
							ci = ci + 1;
						end
					end
				end
			end
			x0 = x0 + 1;
		end
		y0 = y0 + 1;
	end
end
------------------------------------------------------------------------------
function JagWastelandBigDeserts(iW, iH, skip, mirrored)
	local seen = {};
	local frac = Fractal.Create(iW, iH, 4, Map.GetFractalFlags(), -1, -1);
	local edgeCut = frac:GetHeight(56);
	local y0 = 0;
	while y0 < iH do
		local x0 = 0;
		while x0 < iW do
			local i0 = y0 * iW + x0 + 1;
			if seen[i0] ~= true and skip[x0] ~= true and ((not mirrored) or (x0 <= iW * 0.5)) then
				local seed = Map.GetPlot(x0, y0);
				if seed ~= nil and seed:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
					local comp = {};
					local qx = {x0};
					local qy = {y0};
					seen[i0] = true;
					table.insert(comp, seed);
					local qi = 1;
					while qi <= #qx do
						local cx = qx[qi];
						local cy = qy[qi];
						qi = qi + 1;
						local ddir = 0;
						while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(cx, cy, ddir);
							if adj ~= nil then
								local ax = adj:GetX();
								local ay = adj:GetY();
								local ai = ay * iW + ax + 1;
								if seen[ai] ~= true and skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
									if adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
										seen[ai] = true;
										table.insert(comp, adj);
										table.insert(qx, ax);
										table.insert(qy, ay);
									end
								end
							end
							ddir = ddir + 1;
						end
					end
					local n = #comp;
					if n > 8 then
						local target = 8 + math.floor((n - 8) * 0.30);
						if target < 8 then
							target = 8;
						end
						local pass = 0;
						while #comp > target and pass < 24 do
							pass = pass + 1;
							local left = {};
							local ci = 1;
							while ci <= #comp do
								local p = comp[ci];
								if p:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
									local nDes = 0;
									local d = 0;
									while d < DirectionTypes.NUM_DIRECTION_TYPES do
										local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
										if adj ~= nil and adj:GetTerrainType() == TerrainTypes.TERRAIN_DESERT then
											nDes = nDes + 1;
										end
										d = d + 1;
									end
									local hh = frac:GetHeight(p:GetX(), p:GetY());
									local eat = false;
									if nDes <= 4 and hh < edgeCut then
										eat = true;
									end
									if eat then
										p:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
									else
										table.insert(left, p);
									end
								end
								ci = ci + 1;
							end
							if #left >= #comp then
								left = GetShuffledCopyOfTable(left);
								local need = #left - target;
								local k = 1;
								while k <= need and k <= #left do
									left[k]:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
									k = k + 1;
								end
								local kept = {};
								k = need + 1;
								while k <= #left do
									table.insert(kept, left[k]);
									k = k + 1;
								end
								comp = kept;
							else
								comp = left;
							end
						end
					end
				end
			end
			x0 = x0 + 1;
		end
		y0 = y0 + 1;
	end
end
------------------------------------------------------------------------------
local lakeVictoriaFeatureID = nil;
local lakeVictoriaResolved = false;
function GetLakeVictoriaFeatureID()
	if lakeVictoriaResolved then
		return lakeVictoriaFeatureID;
	end
	lakeVictoriaResolved = true;
	local id = GameInfoTypes["FEATURE_LAKE_VICTORIA"];
	if id ~= nil then
		lakeVictoriaFeatureID = id;
		return lakeVictoriaFeatureID;
	end
	for row in GameInfo.Features() do
		if row.NaturalWonder then
			local t = string.upper(tostring(row.Type));
			if string.find(t, "VICTORIA", 1, true) then
				lakeVictoriaFeatureID = row.ID;
				return lakeVictoriaFeatureID;
			end
		end
	end
	return nil;
end
------------------------------------------------------------------------------
function PlotIsWastelandWaterSource(plot)
	if plot == nil then
		return false
	end
	if plot:IsWater() then
		return true
	end
	local vid = GetLakeVictoriaFeatureID();
	if vid ~= nil and plot:GetFeatureType() == vid then
		return true
	end
	return false;
end
------------------------------------------------------------------------------
function FixWastelandFloodPlains()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local nStrip = 0;
	local nAdd = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local feat = plot:GetFeatureType();
					local ter = plot:GetTerrainType();
					if ter ~= TerrainTypes.TERRAIN_DESERT then
						if feat == FeatureTypes.FEATURE_FLOOD_PLAINS or feat == FeatureTypes.FEATURE_OASIS then
							plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
							nStrip = nStrip + 1;
						end
					elseif feat == FeatureTypes.NO_FEATURE and plot:CanHaveFeature(FeatureTypes.FEATURE_FLOOD_PLAINS) then
						plot:SetFeatureType(FeatureTypes.FEATURE_FLOOD_PLAINS, -1);
						nAdd = nAdd + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Wasteland floodplains strip:", nStrip, " add:", nAdd);
end
------------------------------------------------------------------------------
function PeakMassifClear(px, py, minD, iW, iH, skip, mirrored)
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					if Map.PlotDistance(px, py, x, y) < minD then
						return false
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	return true;
end
------------------------------------------------------------------------------
function PeakTouchesForeignMountain(adj, q)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local n = PlotDirNoXWrap(adj:GetX(), adj:GetY(), d);
		if n ~= nil and n:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			local found = false;
			local qi = 1;
			while qi <= #q do
				if q[qi]:GetX() == n:GetX() and q[qi]:GetY() == n:GetY() then
					found = true;
					break
				end
				qi = qi + 1;
			end
			if found == false then
				return true
			end
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakPlotUsable(plot, skip, mirrored, iW, frontBand)
	if plot == nil then
		return false
	end
	local ax = plot:GetX();
	if skip[ax] == true then
		return false
	end
	if WaterAllowedAtX(ax) == false then
		return false
	end
	if frontBand ~= nil and frontBand[ax] == true then
		return false
	end
	if mirrored and ax > iW * 0.5 then
		return false
	end
	if plot:IsWater() then
		return false
	end
	if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	return true;
end
------------------------------------------------------------------------------
function PeakBlobTargetSize()
	-- Mid/Big bases dropped by 1 each (Tiny left alone, already the floor) --
	-- weighted by their 65%/15% roll odds that's exactly a 0.8 reduction in
	-- the average massif size (5.2 -> 4.4 mountains per peak).
	local r = Map.Rand(100, "Peaks Blob Size");
	if r < 20 then
		return 2 + Map.Rand(2, "Peaks Blob Tiny");
	end
	if r < 85 then
		return 4 + Map.Rand(2, "Peaks Blob Mid");
	end
	return 6 + Map.Rand(2, "Peaks Blob Big");
end
------------------------------------------------------------------------------
function PeakCountBlobNeighbors(plot, q)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil then
			local qi = 1;
			while qi <= #q do
				if q[qi]:GetX() == adj:GetX() and q[qi]:GetY() == adj:GetY() then
					n = n + 1;
					break
				end
				qi = qi + 1;
			end
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function PeakGrowFromSeed(seed, target, skip, mirrored, iW, frontBand)
	local q = {};
	table.insert(q, seed);
	seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
	seed:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
	local qi = 1;
	local grown = 1;
	while qi <= #q and grown < target do
		local p = q[qi];
		qi = qi + 1;
		local d0 = Map.Rand(DirectionTypes.NUM_DIRECTION_TYPES, "Peaks Blob Dir");
		local k = 0;
		while k < DirectionTypes.NUM_DIRECTION_TYPES and grown < target do
			local d = d0 + k;
			if d >= DirectionTypes.NUM_DIRECTION_TYPES then
				d = d - DirectionTypes.NUM_DIRECTION_TYPES;
			end
			local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
			if adj ~= nil then
				local cand = adj;
				if Map.Rand(100, "Peaks Blob Skip") < 26 then
					local far = PlotDirNoXWrap(adj:GetX(), adj:GetY(), d);
					if far ~= nil then
						cand = far;
					end
				end
				if PeakPlotUsable(cand, skip, mirrored, iW, frontBand) then
					if PeakTouchesForeignMountain(cand, q) == false then
						local packed = PeakCountBlobNeighbors(cand, q);
						local allow = true;
						if packed >= 3 and Map.Rand(100, "Peaks Blob Pack") >= 20 then
							allow = false;
						end
						if allow and Map.Rand(100, "Peaks Blob Grow") < 76 then
							cand:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
							cand:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							table.insert(q, cand);
							grown = grown + 1;
						end
					end
				end
			end
			k = k + 1;
		end
	end
	return q;
end
------------------------------------------------------------------------------
function PeakTouchesForeignWater(adj, q)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local n = PlotDirNoXWrap(adj:GetX(), adj:GetY(), d);
		if n ~= nil and n:IsWater() then
			local found = false;
			local qi = 1;
			while qi <= #q do
				if q[qi]:GetX() == n:GetX() and q[qi]:GetY() == n:GetY() then
					found = true;
					break
				end
				qi = qi + 1;
			end
			if found == false then
				return true
			end
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakGrowWaterFromSeed(seed, target, skip, mirrored, iW, iH, frontBand)
	local q = {};
	table.insert(q, seed);
	seed:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
	seed:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
	seed:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
	local qi = 1;
	local grown = 1;
	while qi <= #q and grown < target do
		local p = q[qi];
		qi = qi + 1;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
			if adj ~= nil and grown < target then
				local ay = adj:GetY();
				if ay >= 2 and ay < iH - 2 then
					if PeakPlotUsable(adj, skip, mirrored, iW, frontBand) then
						if PeakTouchesForeignWater(adj, q) == false then
							if Map.Rand(100, "Peaks Pond Grow") < 80 then
								adj:SetPlotType(PlotTypes.PLOT_OCEAN, false, false);
								adj:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false);
								adj:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
								table.insert(q, adj);
								grown = grown + 1;
							end
						end
					end
				end
			end
			d = d + 1;
		end
	end
	return q;
end
------------------------------------------------------------------------------
function PeakRevertWater(q)
	local i = 1;
	while i <= #q do
		q[i]:SetPlotType(PlotTypes.PLOT_LAND, false, false);
		q[i]:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
		q[i]:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function PeakPondTwinSeed(water, mountains, skip, mirrored, iW, frontBand)
	if #water < 1 or #mountains < 1 then
		return nil
	end
	local cx = 0;
	local cy = 0;
	local mi = 1;
	while mi <= #mountains do
		cx = cx + mountains[mi]:GetX();
		cy = cy + mountains[mi]:GetY();
		mi = mi + 1;
	end
	cx = math.floor(cx / #mountains + 0.5);
	cy = math.floor(cy / #mountains + 0.5);
	local best = nil;
	local bestD = -1;
	local wi = 1;
	while wi <= #water do
		local ddir = 0;
		while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(water[wi]:GetX(), water[wi]:GetY(), ddir);
			if PeakPlotUsable(adj, skip, mirrored, iW, frontBand) then
				if PeakTouchesForeignMountain(adj, {}) == false then
					local d = Map.PlotDistance(adj:GetX(), adj:GetY(), cx, cy);
					if d > bestD then
						bestD = d;
						best = adj;
					end
				end
			end
			ddir = ddir + 1;
		end
		wi = wi + 1;
	end
	return best;
end
------------------------------------------------------------------------------
function PeakTryDoublePeak(q, skip, mirrored, iW, iH, frontBand)
	local nWater = 4 + Map.Rand(3, "Peaks Pond Size");
	local starts = GetShuffledCopyOfTable(q);
	local si = 1;
	while si <= #starts do
		local d0 = Map.Rand(DirectionTypes.NUM_DIRECTION_TYPES, "Peaks Pond Dir");
		local k = 0;
		while k < DirectionTypes.NUM_DIRECTION_TYPES do
			local dir = d0 + k;
			if dir >= DirectionTypes.NUM_DIRECTION_TYPES then
				dir = dir - DirectionTypes.NUM_DIRECTION_TYPES;
			end
			local seed = PlotDirNoXWrap(starts[si]:GetX(), starts[si]:GetY(), dir);
			local sy = -1;
			if seed ~= nil then
				sy = seed:GetY();
			end
			if sy >= 2 and sy < iH - 2 and PeakPlotUsable(seed, skip, mirrored, iW, frontBand) then
				if Map.FindWater(seed, 2, false) == false then
					local water = PeakGrowWaterFromSeed(seed, nWater, skip, mirrored, iW, iH, frontBand);
					if #water >= 3 then
						local twin = PeakPondTwinSeed(water, q, skip, mirrored, iW, frontBand);
						if twin ~= nil then
							return PeakGrowFromSeed(twin, PeakBlobTargetSize(), skip, mirrored, iW, frontBand)
						end
					end
					PeakRevertWater(water);
				end
			end
			k = k + 1;
		end
		si = si + 1;
	end
	return nil;
end
------------------------------------------------------------------------------
function PeakRollMassifKnobs()
	nPeakMassifs = nPeakMassifs + 1;
	local id = nPeakMassifs;
	-- Thresholds nudged up from their previous values (fewer tiles clear the
	-- now-higher fractal-percentile bar, so the collar reads slightly
	-- thinner) and widened a little for more massif-to-massif variety.
	if Map.Rand(2, "Peaks Hill Style") == 0 then
		peakHillStyle[id] = 1;
		peakHillT1[id] = 0;
		peakHillT2[id] = 28 + Map.Rand(20, "Peaks Thick T2");
		peakHillT3[id] = 92 + Map.Rand(8, "Peaks Thick T3");
	else
		peakHillStyle[id] = 2;
		peakHillT1[id] = 32 + Map.Rand(26, "Peaks Spike T1");
		peakHillT2[id] = 46 + Map.Rand(22, "Peaks Spike T2");
		peakHillT3[id] = 62 + Map.Rand(24, "Peaks Spike T3");
	end
	local fr = Map.Rand(100, "Peaks Forest Style");
	if fr < 38 then
		peakForestStyle[id] = 1;
	elseif fr < 72 then
		peakForestStyle[id] = 2;
	else
		peakForestStyle[id] = 3;
	end
	return id;
end
------------------------------------------------------------------------------
function PeakRollFrontKnobs()
	nPeakMassifs = nPeakMassifs + 1;
	local id = nPeakMassifs;
	peakHillStyle[id] = 2;
	peakHillT1[id] = 50 + Map.Rand(20, "Peaks Front T1");
	peakHillT2[id] = 70 + Map.Rand(15, "Peaks Front T2");
	peakHillT3[id] = 88 + Map.Rand(10, "Peaks Front T3");
	peakForestStyle[id] = 1;
	return id;
end
------------------------------------------------------------------------------
function PeakStampMassif(q, id)
	local iW = Map.GetGridSize();
	local i = 1;
	while i <= #q do
		local p = q[i];
		peakMassif[p:GetY() * iW + p:GetX() + 1] = id;
		i = i + 1;
	end
end
------------------------------------------------------------------------------
function PeakStampConnectedMountains(sx, sy, id, iW, iH, skip, mirrored)
	local qx = {sx};
	local qy = {sy};
	peakMassif[sy * iW + sx + 1] = id;
	local qi = 1;
	while qi <= #qx do
		local cx = qx[qi];
		local cy = qy[qi];
		qi = qi + 1;
		local ddir = 0;
		while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(cx, cy, ddir);
			if adj ~= nil then
				local ax = adj:GetX();
				local ay = adj:GetY();
				local ai = ay * iW + ax + 1;
				if skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
					if adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN and peakMassif[ai] == nil then
						peakMassif[ai] = id;
						qx[#qx + 1] = ax;
						qy[#qy + 1] = ay;
					end
				end
			end
			ddir = ddir + 1;
		end
	end
end
------------------------------------------------------------------------------
function PeakAssignUntaggedMassifs(iW, iH, skip, mirrored)
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local i = y * iW + x + 1;
				if peakMassif[i] == nil then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						PeakStampConnectedMountains(x, y, PeakRollFrontKnobs(), iW, iH, skip, mirrored);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
end
------------------------------------------------------------------------------
function AddPeaksLayout()
	peakDist = {};
	peakNX = {};
	peakNY = {};
	peakMassif = {};
	peakHillStyle = {};
	peakHillT1 = {};
	peakHillT2 = {};
	peakHillT3 = {};
	peakForestStyle = {};
	nPeakMassifs = 0;
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mid = math.floor(iW / 2);
	local frontBand = {};
	frontBand[mid - 5] = true;
	frontBand[mid - 4] = true;
	frontBand[mid - 3] = true;
	frontBand[mid + 2] = true;
	frontBand[mid + 3] = true;
	frontBand[mid + 4] = true;
	if IsSnowWrapX() then
		local xWest, xEast = GetSnowWrapLandMountainXs(iW);
		frontBand[xWest - 1] = true;
		frontBand[xWest] = true;
		frontBand[xWest + 1] = true;
		frontBand[xEast - 1] = true;
		frontBand[xEast] = true;
		frontBand[xEast + 1] = true;
	end
	local noBlob = {};
	local bx = 0;
	while bx < iW do
		if frontBand[bx] == true then
			noBlob[bx] = true;
		end
		bx = bx + 1;
	end
	local sc = GetSnowWrapColumns(iW);
	local sci = 1;
	while sci <= #sc do
		noBlob[sc[sci]] = true;
		sci = sci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local land = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					local keepFront = (frontBand[x] == true and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN);
					if keepFront == false then
						if plot:GetPlotType() ~= PlotTypes.PLOT_LAND then
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
						end
					end
					if keepFront == false and noBlob[x] ~= true and y >= 2 and y < iH - 2 then
						table.insert(land, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	land = GetShuffledCopyOfTable(land);
	local nBlobs = 5 + Map.Rand(4, "Peaks Massif Count");
	local blobN = 0;
	local nPlaced = 0;
	local nDouble = 0;
	local pass = 1;
	local minClear = 6;
	while pass <= 2 and nPlaced < nBlobs do
		if pass == 2 then
			minClear = 4;
			land = GetShuffledCopyOfTable(land);
		end
		local li = 1;
		while nPlaced < nBlobs and li <= #land do
			local seed = land[li];
			li = li + 1;
			if seed:IsWater() == false and seed:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
				local px = seed:GetX();
				local py = seed:GetY();
				if PeakMassifClear(px, py, minClear, iW, iH, skip, mirrored) then
					local q = PeakGrowFromSeed(seed, PeakBlobTargetSize(), skip, mirrored, iW, noBlob);
					blobN = blobN + #q;
					nPlaced = nPlaced + 1;
					PeakStampMassif(q, PeakRollMassifKnobs());
					local didDouble = false;
					if nDouble < 1 and nPlaced == 1 and Map.Rand(100, "Peaks Double") < 18 then
						local q2 = PeakTryDoublePeak(q, skip, mirrored, iW, iH, noBlob);
						if q2 ~= nil then
							blobN = blobN + #q2;
							nPlaced = nPlaced + 1;
							nDouble = nDouble + 1;
							didDouble = true;
							PeakStampMassif(q2, PeakRollMassifKnobs());
						end
					end
					if didDouble == false and #q >= 8 then
						local west = q[1];
						local east = q[1];
						local wi = 1;
						while wi <= #q do
							if q[wi]:GetX() < west:GetX() then
								west = q[wi];
							end
							if q[wi]:GetX() > east:GetX() then
								east = q[wi];
							end
							wi = wi + 1;
						end
						WalkMireCorridor(west:GetX(), west:GetY(), east:GetX(), east:GetY(), skip, 0, iW, 20);
						west:SetPlotType(PlotTypes.PLOT_LAND, false, false);
						east:SetPlotType(PlotTypes.PLOT_LAND, false, false);
					end
				end
			end
		end
		pass = pass + 1;
	end
	PeakAssignUntaggedMassifs(iW, iH, skip, mirrored);
	local INF = 99;
	local dist = {};
	local nx = {};
	local ny = {};
	local mz = {};
	local qx = {};
	local qy = {};
	local qn = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			dist[i] = INF;
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
					dist[i] = 0;
					nx[i] = x;
					ny[i] = y;
					mz[i] = peakMassif[i];
					qn = qn + 1;
					qx[qn] = x;
					qy[qn] = y;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local qi = 1;
	while qi <= qn do
		local cx = qx[qi];
		local cy = qy[qi];
		local ci = cy * iW + cx + 1;
		local cd = dist[ci];
		qi = qi + 1;
		local ddir = 0;
		while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(cx, cy, ddir);
			if adj ~= nil then
				local ax = adj:GetX();
				local ay = adj:GetY();
				if skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
					local ai = ay * iW + ax + 1;
					if dist[ai] > cd + 1 then
						dist[ai] = cd + 1;
						nx[ai] = nx[ci];
						ny[ai] = ny[ci];
						mz[ai] = mz[ci];
						qn = qn + 1;
						qx[qn] = ax;
						qy[qn] = ay;
					end
				end
			end
			ddir = ddir + 1;
		end
	end
	local hillFrac = Fractal.Create(iW, iH, 5, Map.GetFractalFlags(), -1, -1);
	-- Independent, differently-grained noise field layered on top of the
	-- smooth per-massif-style collar below, so its edge reads as ragged and
	-- organic instead of a clean concentric ring: a chance to drop a tile
	-- the style/threshold check would have made a hill, and a chance to add
	-- one it wouldn't have -- extended out to d==4/5, which the style
	-- thresholds never touch at all otherwise (nothing between the d<=3
	-- collar and the sparse d>=6 far-hill roll).
	local noiseFrac = Fractal.Create(iW, iH, 6, Map.GetFractalFlags(), -1, -1);
	local noiseLoThresh = noiseFrac:GetHeight(14);
	local noiseHiThresh = noiseFrac:GetHeight(92);
	local nHill = 0;
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			peakDist[i] = dist[i];
			peakNX[i] = nx[i];
			peakNY[i] = ny[i];
			if mz[i] ~= nil then
				peakMassif[i] = mz[i];
			end
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
						plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
					else
						local d = dist[i];
						local makeHill = false;
						if d < INF then
							local id = mz[i];
							local st = 1;
							local p1 = 0;
							local p2 = 32;
							local p3 = 92;
							if id ~= nil and peakHillStyle[id] ~= nil then
								st = peakHillStyle[id];
								p1 = peakHillT1[id];
								p2 = peakHillT2[id];
								p3 = peakHillT3[id];
							end
							local hh = hillFrac:GetHeight(x, y);
							if st == 1 then
								if d == 1 then
									makeHill = true;
								elseif d == 2 and hh >= hillFrac:GetHeight(p2) then
									makeHill = true;
								elseif d == 3 and hh >= hillFrac:GetHeight(p3) then
									makeHill = true;
								end
							else
								if d == 1 and hh >= hillFrac:GetHeight(p1) then
									makeHill = true;
								elseif d == 2 and hh >= hillFrac:GetHeight(p2) then
									makeHill = true;
								elseif d == 3 and hh >= hillFrac:GetHeight(p3) then
									makeHill = true;
								end
							end
						end
						if d < INF and d <= 5 then
							local nz = noiseFrac:GetHeight(x, y);
							if nz < noiseLoThresh then
								makeHill = false;
							elseif nz >= noiseHiThresh then
								makeHill = true;
							end
						end
						if makeHill == false and d >= 6 and d < INF and Map.Rand(100, "Peaks Far Hill") < 8 then
							makeHill = true;
						end
						if makeHill then
							plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
							nHill = nHill + 1;
						else
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
							plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Peaks blobs mountains:", blobN, " hill collar:", nHill, " massifs:", nPlaced, " rolled:", nBlobs, " doubles:", nDouble, " styles:", nPeakMassifs);
	PeakFlattenFrontTundraHills();
	PeakScatterFrontRelief();
	AddPeaksStrayMountains();
	AddPeaksRainShadowDesert();
	AddPeaksBackCoastIslands();
end
------------------------------------------------------------------------------
-- Populates the back-coast corner blob ShapeNoWrapBackstrip carves for
-- Peaky (see its own peaks branch, and ResolveSaltWaterPlan's matching
-- cutPct/corner-anchoring) with one proper peak-island (a small connected
-- massif with its own hill/land collar, echoing the inland massifs) plus a
-- handful of tiny splintered cliffs -- not a dense scatter of tiny islets,
-- which read as clutter once the coast stopped being a thin full-height
-- stretch and became a compact blob. Deliberately NOT done at the
-- plotTypes-array stage inside ShapeNoWrapBackstrip itself: that runs
-- before AddPeaksLayout's own land-flatten pass above, which would just
-- wipe any land/mountain placed there straight back to flat land. Running
-- after AddPeaksLayout instead means everything here operates on committed
-- Map plots that nothing downstream resets.
function AddPeaksBackCoastIslands()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	-- Must match ShapeNoWrapBackstrip's own peaks backMax so islands can use
	-- the full carved depth of the coast.
	local bandMax = 8;
	local function touchesMainland(plot)
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
			if adj ~= nil and adj:IsWater() == false and adj:GetX() > bandMax then
				return true
			end
			d = d + 1;
		end
		return false;
	end
	local function touchesLand(plot)
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
			if adj ~= nil and adj:IsWater() == false then
				return true
			end
			d = d + 1;
		end
		return false;
	end
	local claimed = {};
	local function isClaimed(x, y)
		return claimed[y * iW + x] == true;
	end
	local function claimWithMoat(footprint)
		local fi = 1;
		while fi <= #footprint do
			local fx, fy = footprint[fi][1], footprint[fi][2];
			claimed[fy * iW + fx] = true;
			local dd = 0;
			while dd < DirectionTypes.NUM_DIRECTION_TYPES do
				local madj = PlotDirNoXWrap(fx, fy, dd);
				if madj ~= nil then
					claimed[madj:GetY() * iW + madj:GetX()] = true;
				end
				dd = dd + 1;
			end
			fi = fi + 1;
		end
	end
	local function gatherCandidates()
		local cands = {};
		local y = 2;
		while y < iH - 2 do
			local x = 0;
			while x <= bandMax do
				if MirrorOwnsPlot(x, y, mirrored, iW) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() and isClaimed(x, y) == false
						and touchesMainland(plot) == false and touchesLand(plot) == false then
						table.insert(cands, plot);
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		return GetShuffledCopyOfTable(cands);
	end
	-- Small hill/land halo around a footprint, matching the inland massifs'
	-- own collar vibe instead of reading as a bare rock.
	local function growHalo(footprint, seed, isPeak, haloTarget)
		local sx, sy = seed:GetX(), seed:GetY();
		local haloGrown = 0;
		local d0 = Map.Rand(DirectionTypes.NUM_DIRECTION_TYPES, "Peaks BackCoast Island Halo Dir");
		local k = 0;
		while k < DirectionTypes.NUM_DIRECTION_TYPES and haloGrown < haloTarget do
			local d = (d0 + k) % DirectionTypes.NUM_DIRECTION_TYPES;
			k = k + 1;
			local adj = PlotDirNoXWrap(sx, sy, d);
			if adj ~= nil and adj:GetX() <= bandMax and adj:IsWater()
				and isClaimed(adj:GetX(), adj:GetY()) == false
				and touchesMainland(adj) == false then
				if isPeak and Map.Rand(2, "Peaks BackCoast Island Halo Type") == 0 then
					adj:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
				else
					adj:SetPlotType(PlotTypes.PLOT_LAND, false, false);
				end
				adj:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
				table.insert(footprint, {adj:GetX(), adj:GetY()});
				haloGrown = haloGrown + 1;
			end
		end
	end
	-- The one proper peak island: a small connected mountain massif (3-5
	-- tiles), not just a single splinter, with a real 2-3 tile collar.
	local nPeakPlaced = 0;
	local candidates = gatherCandidates();
	local ci = 1;
	while nPeakPlaced < 1 and ci <= #candidates do
		local seed = candidates[ci];
		ci = ci + 1;
		if seed:IsWater() and isClaimed(seed:GetX(), seed:GetY()) == false then
			local target = 3 + Map.Rand(3, "Peaks BackCoast Peak Island Size");
			local footprint = {{seed:GetX(), seed:GetY()}};
			seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
			seed:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
			local qi = 1;
			while qi <= #footprint and #footprint < target do
				local px, py = footprint[qi][1], footprint[qi][2];
				local d0 = Map.Rand(DirectionTypes.NUM_DIRECTION_TYPES, "Peaks BackCoast Peak Island Grow Dir");
				local k = 0;
				while k < DirectionTypes.NUM_DIRECTION_TYPES and #footprint < target do
					local d = (d0 + k) % DirectionTypes.NUM_DIRECTION_TYPES;
					k = k + 1;
					local adj = PlotDirNoXWrap(px, py, d);
					if adj ~= nil and adj:GetX() <= bandMax and adj:IsWater()
						and isClaimed(adj:GetX(), adj:GetY()) == false
						and touchesMainland(adj) == false
						and Map.Rand(100, "Peaks BackCoast Peak Island Grow") < 70 then
						adj:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
						adj:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						table.insert(footprint, {adj:GetX(), adj:GetY()});
					end
				end
				qi = qi + 1;
			end
			growHalo(footprint, seed, true, 2 + Map.Rand(2, "Peaks BackCoast Peak Island Halo"));
			claimWithMoat(footprint);
			nPeakPlaced = 1;
		end
	end
	-- A handful of tiny splintered cliffs sprinkled around the same blob --
	-- mostly bare rock (rarely a token 1-tile halo), distinct from the one
	-- proper peak island above.
	local nSplinterTarget = 3 + Map.Rand(4, "Peaks BackCoast Splinter Count");
	local nSplinterPlaced = 0;
	candidates = gatherCandidates();
	ci = 1;
	while nSplinterPlaced < nSplinterTarget and ci <= #candidates do
		local seed = candidates[ci];
		ci = ci + 1;
		if seed:IsWater() and isClaimed(seed:GetX(), seed:GetY()) == false then
			local footprint = {{seed:GetX(), seed:GetY()}};
			seed:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
			seed:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
			if Map.Rand(100, "Peaks BackCoast Splinter Halo Chance") < 30 then
				growHalo(footprint, seed, true, 1);
			end
			claimWithMoat(footprint);
			nSplinterPlaced = nSplinterPlaced + 1;
		end
	end
	print("Peaks back-coast islands: peak island=", nPeakPlaced, " splinters=", nSplinterPlaced, "/", nSplinterTarget);
end
------------------------------------------------------------------------------
function AddPeaksRainShadowDesert()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nWant = 1;
	if Map.Rand(100, "Peaks Desert Count") < 40 then
		nWant = 2;
	end
	local n = 0;
	local p = 0;
	while p < nWant do
		local cands = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) and y < iH * 0.58 and y >= 2 then
					local i = y * iW + x + 1;
					local dpk = peakDist[i];
					if dpk ~= nil and dpk >= 2 and dpk <= 5 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							if plot:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS then
								local nearTundra = false;
								local dd = 0;
								while dd < DirectionTypes.NUM_DIRECTION_TYPES do
									local adj = PlotDirNoXWrap(x, y, dd);
									if adj ~= nil and adj:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
										nearTundra = true;
									end
									dd = dd + 1;
								end
								if nearTundra == false then
									table.insert(cands, plot);
								end
							end
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands < 1 then
			break
		end
		local seed = cands[1 + Map.Rand(#cands, "Peaks Desert Seed")];
		local q = {seed};
		seed:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
		local grown = 1;
		local target = 4 + Map.Rand(5, "Peaks Desert Size");
		local qi = 1;
		while qi <= #q and grown < target do
			local plot = q[qi];
			qi = qi + 1;
			local ddir = 0;
			while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), ddir);
				if adj ~= nil and grown < target then
					local ax = adj:GetX();
					local ay = adj:GetY();
					if skip[ax] ~= true and MirrorOwnsPlot(ax, ay, mirrored, iW) and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if adj:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS then
							if Map.Rand(100, "Peaks Desert Grow") < 70 then
								adj:SetTerrainType(TerrainTypes.TERRAIN_DESERT, false, false);
								table.insert(q, adj);
								grown = grown + 1;
							end
						end
					end
				end
				ddir = ddir + 1;
			end
		end
		n = n + grown;
		p = p + 1;
	end
	print("Peaks rain-shadow desert tiles:", n, " pockets:", p);
end
------------------------------------------------------------------------------
function PeakTouchesMountain(plot)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
			return true
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakFlattenFrontTundraHills()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local cols = GetSnowWrapTundraColumns(iW);
	local n = 0;
	local ci = 1;
	while ci <= #cols do
		local x = cols[ci];
		if x >= 0 and x < iW and ((DEF_MIRRORED ~= 1) or (x <= iW * 0.5)) then
			local y = 0;
			while y < iH do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_HILLS then
					if PeakTouchesMountain(plot) == false then
						if Map.Rand(100, "Peaks Tundra Flatten") < 85 then
							plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
							n = n + 1;
						end
					end
				end
				y = y + 1;
			end
		end
		ci = ci + 1;
	end
	print("Peaks front tundra flatten:", n);
end
------------------------------------------------------------------------------
function PeakScatterFrontRelief()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local cols = GetSnowWrapTundraColumns(iW);
	local nHill = 0;
	local nMtn = 0;
	local ci = 1;
	while ci <= #cols do
		local x = cols[ci];
		if x >= 0 and x < iW and ((DEF_MIRRORED ~= 1) or (x <= iW * 0.5)) then
			local y = 0;
			while y < iH do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND then
					local pt = Map.Rand(100, "Peaks Tundra Scatter");
					if pt < 3 then
						plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
						nMtn = nMtn + 1;
					elseif pt < 17 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						nHill = nHill + 1;
					end
				end
				y = y + 1;
			end
		end
		ci = ci + 1;
	end
	print("Peaks front tundra scatter hills:", nHill, " peaks:", nMtn);
end
------------------------------------------------------------------------------
function PeakReliefWithin(x, y, maxD)
	local dy = y - maxD;
	while dy <= y + maxD do
		local dx = x - maxD;
		while dx <= x + maxD do
			if Map.PlotDistance(x, y, dx, dy) <= maxD then
				local p = Map.GetPlot(dx, dy);
				if p ~= nil then
					local pt = p:GetPlotType();
					if pt == PlotTypes.PLOT_HILLS or pt == PlotTypes.PLOT_MOUNTAIN then
						return true
					end
				end
			end
			dx = dx + 1;
		end
		dy = dy + 1;
	end
	return false
end
------------------------------------------------------------------------------
function AddPeaksStrayMountains()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local cands = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local i = y * iW + x + 1;
				local d = peakDist[i];
				if d ~= nil and d >= 4 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND then
						if PeakReliefWithin(x, y, 2) == false then
							table.insert(cands, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #cands < 1 then
		return
	end
	cands = GetShuffledCopyOfTable(cands);
	local n = 0;
	local i = 1;
	while i <= #cands do
		local plot = cands[i];
		if plot:GetPlotType() == PlotTypes.PLOT_LAND then
			if PeakReliefWithin(plot:GetX(), plot:GetY(), 2) == false then
				if Map.Rand(100, "Peaks Stray Mountain") < 5 then
					plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
					n = n + 1;
				end
			end
		end
		i = i + 1;
	end
	print("Peaks stray mountains:", n);
end
------------------------------------------------------------------------------
function AddPeaksNorthTundra()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local n = 0;
	local y = iH - 1;
	while y >= iH - 3 and y >= 0 do
		local depth = iH - 1 - y;
		local chance = 78;
		if depth == 1 then
			chance = 48;
		elseif depth == 2 then
			chance = 22;
		end
		local x = 0;
		while x < iW do
			if skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					local bump = 0;
					local d = 0;
					while d < DirectionTypes.NUM_DIRECTION_TYPES do
						local adj = PlotDirNoXWrap(x, y, d);
						if adj ~= nil and adj:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
							bump = bump + 12;
						end
						d = d + 1;
					end
					if Map.Rand(100, "Peaks North Tundra") < chance + bump then
						plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y - 1;
	end
	y = iH - 4;
	if y < 0 then
		y = 0;
	end
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					if plot:GetTerrainType() == TerrainTypes.TERRAIN_GRASS then
						local d = 0;
						while d < DirectionTypes.NUM_DIRECTION_TYPES do
							local adj = PlotDirNoXWrap(x, y, d);
							if adj ~= nil and adj:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
								plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
								break
							end
							d = d + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Peaks north tundra:", n);
end
------------------------------------------------------------------------------
function AddPeaksFrontStrayForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local mid = math.floor(iW / 2);
	local cands = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local dx = x - mid;
				if dx < 0 then
					dx = 0 - dx;
				end
				if dx <= 7 then
					local i = y * iW + x + 1;
					local d = peakDist[i];
					if d ~= nil and d >= 1 and d <= 3 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
								table.insert(cands, plot);
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #cands < 1 then
		return
	end
	cands = GetShuffledCopyOfTable(cands);
	local nWant = 5 + Map.Rand(5, "Peaks Front Forest Count");
	if nWant > #cands then
		nWant = #cands;
	end
	local n = 0;
	local i = 1;
	while i <= nWant do
		cands[i]:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
		n = n + 1;
		if Map.Rand(100, "Peaks Front Forest Grow") < 40 then
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(cands[i]:GetX(), cands[i]:GetY(), d);
				if adj ~= nil and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if adj:GetFeatureType() == FeatureTypes.NO_FEATURE and skip[adj:GetX()] ~= true then
						adj:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						n = n + 1;
						break
					end
				end
				d = d + 1;
			end
		end
		i = i + 1;
	end
	print("Peaks front stray forests:", n);
end
------------------------------------------------------------------------------
-- AddPeaksFrontStrayForests only scatters forest within 7 columns of the
-- barrier's own front (peakDist 1-3, i.e. near-front massifs specifically).
-- Peaks massifs are scattered across the whole west half though, so most of
-- the map's flat land sits far from any massif and this never touched it --
-- this is the "away from the peaks" counterpart, using the same peakDist
-- field but inverted (far from any mountain) and with no column bound.
function AddPeaksInteriorStrayForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local cands = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local i = y * iW + x + 1;
				local d = peakDist[i];
				if d ~= nil and d >= 5 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
						if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
							table.insert(cands, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #cands < 1 then
		return
	end
	cands = GetShuffledCopyOfTable(cands);
	local nWant = math.floor(#cands * 0.06 + 0.5);
	if nWant < 1 then
		nWant = 1;
	end
	if nWant > #cands then
		nWant = #cands;
	end
	local n = 0;
	local i = 1;
	while i <= nWant do
		cands[i]:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
		n = n + 1;
		if Map.Rand(100, "Peaks Interior Forest Grow") < 40 then
			local d = 0;
			while d < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(cands[i]:GetX(), cands[i]:GetY(), d);
				if adj ~= nil and adj:IsWater() == false and adj:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if adj:GetFeatureType() == FeatureTypes.NO_FEATURE and skip[adj:GetX()] ~= true then
						adj:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						n = n + 1;
						break
					end
				end
				d = d + 1;
			end
		end
		i = i + 1;
	end
	print("Peaks interior stray forests:", n, "/", #cands, " candidates");
end
------------------------------------------------------------------------------
function AddPeaksThawRiverTundra()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false and plot:IsRiver() then
					if plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA then
						plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
						n = n + 1;
					elseif plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
						plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Peaks river tundra thaw:", n);
end
------------------------------------------------------------------------------
function AddPeaksEconHillFill()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local centers = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					table.insert(centers, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #centers < 1 then
		return
	end
	centers = GetShuffledCopyOfTable(centers);
	local n = 0;
	local ci = 1;
	while ci <= #centers do
		local cx = centers[ci]:GetX();
		local cy = centers[ci]:GetY();
		local nHill = 0;
		local flats = {};
		local dy = cy - 3;
		while dy <= cy + 3 do
			local dx = cx - 3;
			while dx <= cx + 3 do
				if Map.PlotDistance(cx, cy, dx, dy) <= 3 then
					if skip[dx] ~= true and MirrorOwnsPlot(dx, dy, mirrored, iW) then
						local p = Map.GetPlot(dx, dy);
						if p ~= nil and p:IsWater() == false then
							local pt = p:GetPlotType();
							if pt == PlotTypes.PLOT_HILLS then
								nHill = nHill + 1;
							elseif pt == PlotTypes.PLOT_LAND then
								table.insert(flats, p);
							end
						end
					end
				end
				dx = dx + 1;
			end
			dy = dy + 1;
		end
		if nHill < 3 and #flats > 0 then
			local pick = flats[Map.Rand(#flats, "Peaks Econ Hill") + 1];
			pick:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			n = n + 1;
		end
		ci = ci + 1;
	end
	print("Peaks econ hill fill:", n);
end
------------------------------------------------------------------------------
function PeakAdjGrass(plot)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:IsWater() == false and adj:GetTerrainType() == TerrainTypes.TERRAIN_GRASS then
			return true
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakAdjForest(plot)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
			return true
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakMeadowEligible(plot, skip, mirrored, iW)
	if plot == nil then
		return false
	end
	local ax = plot:GetX();
	if skip[ax] == true then
		return false
	end
	if mirrored and ax > iW * 0.5 then
		return false
	end
	if plot:IsWater() then
		return false
	end
	if plot:GetPlotType() ~= PlotTypes.PLOT_LAND then
		return false
	end
	if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_PLAINS then
		return false
	end
	return true;
end
------------------------------------------------------------------------------
function PeakAdjRiver(plot)
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:IsWater() == false and adj:IsRiver() then
			return true
		end
		d = d + 1;
	end
	return false;
end
------------------------------------------------------------------------------
function PeakGrowMeadow(seed, target, skip, mirrored, iW)
	local q = {};
	table.insert(q, seed);
	seed:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
	local grown = 1;
	local qi = 1;
	while qi <= #q and grown < target do
		local p = q[qi];
		qi = qi + 1;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
			if adj ~= nil and grown < target then
				if PeakMeadowEligible(adj, skip, mirrored, iW) then
					local take = false;
					if adj:IsRiver() then
						if Map.Rand(100, "Peaks Meadow River") < 90 then
							take = true;
						end
					elseif PeakAdjGrass(adj) then
						if PeakAdjRiver(adj) then
							if Map.Rand(100, "Peaks Meadow Bleed") < 72 then
								take = true;
							end
						elseif PeakAdjForest(adj) then
							if Map.Rand(100, "Peaks Meadow Forest") < 30 then
								take = true;
							end
						end
					end
					if take then
						adj:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
						table.insert(q, adj);
						grown = grown + 1;
					end
				end
			end
			d = d + 1;
		end
	end
	return grown;
end
------------------------------------------------------------------------------
function PeakForestCollarEligible(plot, skip, mirrored, iW, massifId)
	if plot == nil then
		return false
	end
	local ax = plot:GetX();
	local ay = plot:GetY();
	if skip[ax] == true then
		return false
	end
	if mirrored and ax > iW * 0.5 then
		return false
	end
	if plot:IsWater() then
		return false
	end
	if plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	if plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE then
		return false
	end
	local di = ay * iW + ax + 1;
	if peakMassif[di] ~= massifId then
		return false
	end
	local d = peakDist[di];
	if d == nil or d < 1 or d > 3 then
		return false
	end
	return true;
end
------------------------------------------------------------------------------
function PeakGrowForest(seed, target, skip, mirrored, iW, massifId)
	local q = {};
	table.insert(q, seed);
	seed:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
	local grown = 1;
	local qi = 1;
	while qi <= #q and grown < target do
		local p = q[qi];
		qi = qi + 1;
		local d = 0;
		while d < DirectionTypes.NUM_DIRECTION_TYPES do
			local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
			if adj ~= nil and grown < target then
				if PeakForestCollarEligible(adj, skip, mirrored, iW, massifId) then
					if Map.Rand(100, "Peaks Forest Blob Grow") < 70 then
						adj:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						table.insert(q, adj);
						grown = grown + 1;
					end
				end
			end
			d = d + 1;
		end
	end
	return grown;
end
------------------------------------------------------------------------------
function ForestMountainsToBareTarget()
	local iW, iH = Map.GetGridSize();
	local tilted = IsTiltedMirrorAxis();
	local mirrored = (DEF_MIRRORED == 1);
	-- West-side only, by design (see feedback_west_side_only_rules): counts
	-- and decides forest/bare only for MirrorOwnsPlot's west half, against
	-- BARE_MOUNTAIN_TARGET directly as the true final (post-mirror) bare
	-- count. The later end-of-generation mirror pass reproduces whatever
	-- this picks onto east untouched, same as everything else in the file.
	--
	-- Non-tilted climates (Standard, Oasis, Murky, Peaky, ...) keep the exact
	-- prior flat skip lookup, computed once. Tilted climates (Standard-Diagonal)
	-- need a per-row skip, since the barrier's column position drifts with the
	-- diagonal fold and FillMireSkip's flat (row-unaware) columns miscount
	-- mountains near the barrier. Scoped to this function only, not FillMireSkip
	-- itself, so the many other non-tilted-only callers of FillMireSkip are
	-- untouched.
	local staticSkip = nil;
	if tilted == false then
		staticSkip = FillMireSkip(iW);
	end
	local bareWant = BARE_MOUNTAIN_TARGET;
	if bareWant < 1 then
		bareWant = 1;
	end
	local mtns = {};
	local y = 0;
	while y < iH do
		local skip = staticSkip;
		if tilted then
			skip = {};
			local cols = GetSnowWrapColumns(iW, y);
			local ci = 1;
			while ci <= #cols do
				skip[cols[ci]] = true;
				ci = ci + 1;
			end
			cols = GetSnowWrapTundraColumns(iW, y);
			ci = 1;
			while ci <= #cols do
				skip[cols[ci]] = true;
				ci = ci + 1;
			end
		end
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN and PlotHasNaturalWonder(plot) ~= true then
					table.insert(mtns, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nMtn = #mtns;
	if nMtn < 1 then
		return
	end
	if bareWant > nMtn then
		bareWant = nMtn;
	end
	local nForest = nMtn - bareWant;
	if nMtn > 1 then
		mtns = GetShuffledCopyOfTable(mtns);
	end
	local nSetForest = 0;
	local nSetJungle = 0;
	local i = 1;
	while i <= nMtn do
		local plot = mtns[i];
		if i <= nForest then
			local wantFeat = FeatureTypes.FEATURE_FOREST;
			if HexNearFeature(plot:GetX(), plot:GetY(), FeatureTypes.FEATURE_JUNGLE, 1) then
				wantFeat = FeatureTypes.FEATURE_JUNGLE;
			end
			if plot:GetFeatureType() ~= wantFeat then
				plot:SetFeatureType(wantFeat, -1);
			end
			if wantFeat == FeatureTypes.FEATURE_JUNGLE then
				nSetJungle = nSetJungle + 1;
			else
				nSetForest = nSetForest + 1;
			end
		else
			local feat = plot:GetFeatureType();
			if feat == FeatureTypes.FEATURE_FOREST or feat == FeatureTypes.FEATURE_JUNGLE then
				plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			end
		end
		i = i + 1;
	end
	-- nMtn/bareWant/nForest are west-side-only totals, directly comparable
	-- to BARE_MOUNTAIN_TARGET as the true final (post-mirror) bare count --
	-- the later mirror pass reproduces this exact pattern onto east.
	local diagLine = "Mountain forest: west mtn=" .. nMtn .. " bare=" .. bareWant .. " forested=" .. nForest
		.. " (forest=" .. nSetForest .. " jungle=" .. nSetJungle .. ")"
		.. " cap=" .. BARE_MOUNTAIN_TARGET;
	print(diagLine);
	WeeveeDbg(diagLine);
	WeeveeDbgPersist(diagLine);
end
------------------------------------------------------------------------------
function AddPeaksMassifForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nBlob = 0;
	local nTiles = 0;
	local id = 1;
	while id <= nPeakMassifs do
		if peakForestStyle[id] == 3 then
			local seeds = {};
			local y = 0;
			while y < iH do
				local x = 0;
				while x < iW do
					local plot = Map.GetPlot(x, y);
					if PeakForestCollarEligible(plot, skip, mirrored, iW, id) then
						table.insert(seeds, plot);
					end
					x = x + 1;
				end
				y = y + 1;
			end
			if #seeds > 0 then
				seeds = GetShuffledCopyOfTable(seeds);
				local nWant = 1;
				if Map.Rand(100, "Peaks Forest Blob Extra") < 22 then
					nWant = 2;
				end
				local b = 0;
				local si = 1;
				while b < nWant and si <= #seeds do
					local seed = seeds[si];
					si = si + 1;
					if seed:GetFeatureType() == FeatureTypes.NO_FEATURE then
						local sz = 7 + Map.Rand(5, "Peaks Forest Blob Size");
						if b > 0 then
							sz = 5 + Map.Rand(3, "Peaks Forest Blob Small");
						end
						nTiles = nTiles + PeakGrowForest(seed, sz, skip, mirrored, iW, id);
						nBlob = nBlob + 1;
						b = b + 1;
					end
				end
			end
		end
		id = id + 1;
	end
	print("Peaks forest blobs:", nBlob, " tiles:", nTiles);
end
------------------------------------------------------------------------------
function AddPeaksBackCoastForest()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local wrapN = ResolveSnowWrapWidths();
	local wrapHalf = wrapN / 2;
	local mid = math.floor(iW / 2);
	local backMax = math.floor(mid * 0.42);
	if wrapHalf > 0 then
		if backMax < wrapHalf + 8 then
			backMax = wrapHalf + 8;
		end
	elseif backMax < 8 then
		backMax = 8;
	end
	local INF = 99;
	local wdist = {};
	local qx = {};
	local qy = {};
	local qn = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			wdist[i] = INF;
			if x <= backMax and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() then
					wdist[i] = 0;
					qn = qn + 1;
					qx[qn] = x;
					qy[qn] = y;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local qi = 1;
	while qi <= qn do
		local cx = qx[qi];
		local cy = qy[qi];
		local cd = wdist[cy * iW + cx + 1];
		qi = qi + 1;
		if cd < 2 then
			local ddir = 0;
			while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(cx, cy, ddir);
				if adj ~= nil then
					local ax = adj:GetX();
					local ay = adj:GetY();
					if ax <= backMax and skip[ax] ~= true and ((not mirrored) or (ax <= iW * 0.5)) then
						local ai = ay * iW + ax + 1;
						if wdist[ai] > cd + 1 then
							wdist[ai] = cd + 1;
							qn = qn + 1;
							qx[qn] = ax;
							qy[qn] = ay;
						end
					end
				end
				ddir = ddir + 1;
			end
		end
	end
	local eligible = {};
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			local wd = wdist[i];
			if wd ~= nil and wd >= 1 and wd <= 2 and skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local dPeak = peakDist[i];
				if dPeak ~= nil and dPeak >= 5 then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND then
						if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
							table.insert(eligible, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	if #eligible < 1 then
		print("Peaks back-coast forest: 0");
		return
	end
	eligible = GetShuffledCopyOfTable(eligible);
	local n = 0;
	local ei = 1;
	while ei <= #eligible do
		local plot = eligible[ei];
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			if Map.Rand(100, "Peaks Back Coast Seed") < 28 then
				plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
				n = n + 1;
			end
		end
		ei = ei + 1;
	end
	local growPass = 0;
	while growPass < 2 do
		ei = 1;
		while ei <= #eligible do
			local plot = eligible[ei];
			if plot:GetFeatureType() == FeatureTypes.NO_FEATURE and PeakAdjForest(plot) then
				if Map.Rand(100, "Peaks Back Coast Grow") < 62 then
					plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
					n = n + 1;
				end
			end
			ei = ei + 1;
		end
		growPass = growPass + 1;
	end
	print("Peaks back-coast forest:", n, "/", #eligible);
end
------------------------------------------------------------------------------
function AddPeaksMeadows()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local riverSeeds = {};
	local forestSeeds = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if PeakMeadowEligible(plot, skip, mirrored, iW) then
				if plot:IsRiver() then
					table.insert(riverSeeds, plot);
				elseif PeakAdjForest(plot) then
					table.insert(forestSeeds, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	riverSeeds = GetShuffledCopyOfTable(riverSeeds);
	forestSeeds = GetShuffledCopyOfTable(forestSeeds);
	local nMeadows = 5 + Map.Rand(4, "Peaks Meadow Count");
	local nGrass = 0;
	local nDone = 0;
	local mi = 1;
	while nDone < nMeadows and mi <= #riverSeeds do
		local seed = riverSeeds[mi];
		mi = mi + 1;
		if seed:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS then
			nGrass = nGrass + PeakGrowMeadow(seed, 8 + Map.Rand(9, "Peaks Meadow Size"), skip, mirrored, iW);
			nDone = nDone + 1;
		end
	end
	local nForest = 0;
	local fi = 1;
	while nForest < 2 and fi <= #forestSeeds do
		local seed = forestSeeds[fi];
		fi = fi + 1;
		if seed:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS then
			if Map.Rand(100, "Peaks Meadow Forest Seed") < 40 then
				nGrass = nGrass + PeakGrowMeadow(seed, 3 + Map.Rand(4, "Peaks Meadow Forest Size"), skip, mirrored, iW);
				nForest = nForest + 1;
			end
		end
	end
	print("Peaks meadows:", nDone, " forest fringes:", nForest, " grass tiles:", nGrass);
end
------------------------------------------------------------------------------
function AddPeaksValleyMarsh()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nWant = 1;
	if Map.Rand(100, "Peaks Marsh Count") < 45 then
		nWant = 2;
	end
	local n = 0;
	local p = 0;
	while p < nWant do
		local cands = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
					local i = y * iW + x + 1;
					local dpk = peakDist[i];
					if dpk ~= nil and dpk >= 2 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() == PlotTypes.PLOT_LAND then
							if plot:GetTerrainType() == TerrainTypes.TERRAIN_GRASS and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
								if plot:IsRiver() or PeakAdjRiver(plot) then
									table.insert(cands, plot);
								end
							end
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		if #cands < 1 then
			break
		end
		local seed = cands[1 + Map.Rand(#cands, "Peaks Marsh Seed")];
		local q = {seed};
		seed:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1);
		local grown = 1;
		local target = 3 + Map.Rand(4, "Peaks Marsh Size");
		local qi = 1;
		while qi <= #q and grown < target do
			local plot = q[qi];
			qi = qi + 1;
			local ddir = 0;
			while ddir < DirectionTypes.NUM_DIRECTION_TYPES do
				local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), ddir);
				if adj ~= nil and grown < target then
					if adj:IsWater() == false and adj:GetPlotType() == PlotTypes.PLOT_LAND and adj:GetTerrainType() == TerrainTypes.TERRAIN_GRASS and adj:GetFeatureType() == FeatureTypes.NO_FEATURE then
						if Map.Rand(100, "Peaks Marsh Grow") < 62 then
							adj:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1);
							table.insert(q, adj);
							grown = grown + 1;
						end
					end
				end
				ddir = ddir + 1;
			end
		end
		n = n + grown;
		p = p + 1;
	end
	print("Peaks valley marsh tiles:", n, " pockets:", p);
end
------------------------------------------------------------------------------
function CountFeatureNeighbors(plot, featureType)
	local n = 0;
	local d = 0;
	while d < DirectionTypes.NUM_DIRECTION_TYPES do
		local adj = PlotDirNoXWrap(plot:GetX(), plot:GetY(), d);
		if adj ~= nil and adj:GetFeatureType() == featureType then
			n = n + 1;
		end
		d = d + 1;
	end
	return n;
end
------------------------------------------------------------------------------
function PlaceClusteredFeature(remaining, featureType, pct, randName)
	local n = #remaining;
	if n < 1 or pct < 1 then
		return 0, n
	end
	local target = math.floor(n * (pct / 100) + 0.5);
	local placed = 0;
	while placed < target and #remaining > 0 do
		local totalWeight = 0;
		local i = 1;
		while i <= #remaining do
			local neigh = CountFeatureNeighbors(remaining[i], featureType);
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			totalWeight = totalWeight + w;
			i = i + 1;
		end
		if totalWeight < 1 then
			break
		end
		local roll = Map.Rand(totalWeight, randName);
		i = 1;
		local picked = false;
		while i <= #remaining do
			local neigh = CountFeatureNeighbors(remaining[i], featureType);
			local w = 1;
			if neigh == 1 then
				w = 6;
			elseif neigh >= 2 then
				w = 10;
			end
			if roll < w then
				remaining[i]:SetFeatureType(featureType, -1);
				table.remove(remaining, i);
				placed = placed + 1;
				picked = true;
				break
			end
			roll = roll - w;
			i = i + 1;
		end
		if picked == false then
			remaining[#remaining]:SetFeatureType(featureType, -1);
			table.remove(remaining, #remaining);
			placed = placed + 1;
		end
	end
	return placed, n
end
------------------------------------------------------------------------------
function IsNearAnyStart(x, y, starts, dist)
	local i = 1;
	while i <= #starts do
		if Map.PlotDistance(x, y, starts[i]:GetX(), starts[i]:GetY()) <= dist then
			return true
		end
		i = i + 1;
	end
	return false
end
------------------------------------------------------------------------------
function AddWastelandTundraForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local plots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
					table.insert(plots, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local placed, n = PlaceClusteredFeature(plots, FeatureTypes.FEATURE_FOREST, 8, "Wasteland Tundra Forest");
	print("Wasteland tundra forests:", placed, "/", n);
end
------------------------------------------------------------------------------
function WastelandMiningLuxFlatTundraToHill()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local mineLux = {};
	local nIds = 0;
	if GameInfo.Improvement_ResourceTypes ~= nil then
		for row in GameInfo.Improvement_ResourceTypes() do
			if row.ImprovementType == "IMPROVEMENT_MINE" then
				local resInfo = GameInfo.Resources[row.ResourceType];
				if resInfo ~= nil and resInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
					mineLux[resInfo.ID] = true;
					nIds = nIds + 1;
				end
			end
		end
	end
	if nIds < 1 then
		local names = {
			"RESOURCE_GOLD", "RESOURCE_SILVER", "RESOURCE_GEMS", "RESOURCE_COPPER",
			"RESOURCE_JADE", "RESOURCE_LAPIS", "RESOURCE_AMBER", "RESOURCE_OBSIDIAN"
		};
		local i = 1;
		while names[i] ~= nil do
			local id = GameInfoTypes[names[i]];
			if id ~= nil then
				mineLux[id] = true;
			end
			i = i + 1;
		end
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local raised = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if (not mirrored) or (x <= iW * 0.5) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
					and mineLux[plot:GetResourceType(-1)] == true then
					if Map.Rand(100, "Wasteland mine lux hill") < 90 then
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						raised = raised + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Wasteland mining lux flat tundra to hill:", raised);
end
------------------------------------------------------------------------------
function EnsureMajorIronHills()
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	if ironID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:IsWater() == false then
				if plot:GetResourceType(-1) == ironID and plot:GetNumResource() >= 4 then
					if plot:GetPlotType() == PlotTypes.PLOT_LAND then
						if plot:GetFeatureType() == FeatureTypes.FEATURE_MARSH then
							plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						end
						plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Major iron flats to hills:", n);
end
------------------------------------------------------------------------------
function WastelandTundraStartHillForest(asp)
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	if asp == nil or asp.startingPlots == nil then
		return
	end
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local deerID = GameInfoTypes["RESOURCE_DEER"];
	local woodID = GameInfoTypes["RESOURCE_HARDWOOD"];
	local iW, iH = Map.GetGridSize();
	local r = 1;
	while asp.startingPlots[r] ~= nil do
		local sp = asp.startingPlots[r];
		local sx = sp[1];
		local sy = sp[2];
		if not (DEF_MIRRORED == 1 and sx > iW * 0.5) then
			local nTundra = 0;
			local nLush = 0;
			local hillForest = 0;
			local ironHills = {};
			local deerFlats = {};
			local blankHills = {};
			local blankFlats = {};
			local y = 0;
			while y < iH do
				local x = 0;
				while x < iW do
					local d = Map.PlotDistance(sx, sy, x, y);
					if d >= 1 and d <= 2 then
						local plot = Map.GetPlot(x, y);
						if plot ~= nil and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
							local ter = plot:GetTerrainType();
							if ter == TerrainTypes.TERRAIN_GRASS or ter == TerrainTypes.TERRAIN_PLAINS then
								nLush = nLush + 1;
							elseif ter == TerrainTypes.TERRAIN_TUNDRA then
								nTundra = nTundra + 1;
							end
							local isHill = (plot:GetPlotType() == PlotTypes.PLOT_HILLS);
							local isForest = (plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST);
							if isHill and isForest then
								hillForest = hillForest + 1;
							end
							local res = plot:GetResourceType(-1);
							if isHill and ironID ~= nil and res == ironID and plot:GetNumResource() >= 4 and isForest == false then
								table.insert(ironHills, plot);
							end
							if isHill == false and isForest and deerID ~= nil and res == deerID then
								table.insert(deerFlats, plot);
							end
							if isHill and res == -1 and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
								table.insert(blankHills, plot);
							end
							if isHill == false and plot:GetPlotType() == PlotTypes.PLOT_LAND and res == -1 and plot:GetFeatureType() == FeatureTypes.NO_FEATURE and ter == TerrainTypes.TERRAIN_TUNDRA then
								table.insert(blankFlats, plot);
							end
						end
					end
					x = x + 1;
				end
				y = y + 1;
			end
			if nTundra >= nLush then
				if #ironHills > 0 and Map.Rand(100, "Wasteland Start Iron Forest") < 55 then
					ironHills = GetShuffledCopyOfTable(ironHills);
					ironHills[1]:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
					hillForest = hillForest + 1;
				end
				if hillForest < 1 and #deerFlats > 0 and Map.Rand(100, "Wasteland Start Deer Hill") < 40 then
					deerFlats = GetShuffledCopyOfTable(deerFlats);
					deerFlats[1]:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
					hillForest = hillForest + 1;
				end
				if hillForest < 1 and Map.Rand(100, "Wasteland Start Hardwood") < 18 then
					local target = nil;
					if #blankHills > 0 then
						blankHills = GetShuffledCopyOfTable(blankHills);
						target = blankHills[1];
					elseif #blankFlats > 0 then
						blankFlats = GetShuffledCopyOfTable(blankFlats);
						target = blankFlats[1];
						target:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
					end
					if target ~= nil then
						target:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
						if woodID ~= nil then
							target:SetResourceType(woodID, 1);
						end
						hillForest = hillForest + 1;
					end
				end
			end
		end
		r = r + 1;
	end
end
------------------------------------------------------------------------------
function AddWastelandFallout()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local falloutType = FeatureTypes.FEATURE_FALLOUT;
	if falloutType == nil then
		falloutType = GameInfoTypes["FEATURE_FALLOUT"];
	end
	if falloutType == nil then
		print("Wasteland fallout: FEATURE_FALLOUT missing");
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local barrierCol = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		barrierCol[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local starts = {};
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() and player:GetStartingPlot() ~= nil then
			table.insert(starts, player:GetStartingPlot());
		end
		pi = pi + 1;
	end
	local barrierPlots = {};
	local nearPlots = {};
	local farPlots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if (not mirrored) or (x <= iW * 0.5) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
					if barrierCol[x] == true then
						table.insert(barrierPlots, plot);
					elseif skip[x] ~= true and IsNearAnyStart(x, y, starts, 3) == false then
						local d = wastelandWaterDist[y * iW + x + 1];
						if d ~= nil and d <= 2 then
							table.insert(nearPlots, plot);
						else
							table.insert(farPlots, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local bPlaced, bN = PlaceClusteredFeature(barrierPlots, falloutType, cfg.falloutBarrierPct, "Wasteland Barrier Fallout");
	local nPlaced, nN = PlaceClusteredFeature(nearPlots, falloutType, cfg.falloutPlayableNearPct, "Wasteland Near Fallout");
	local fPlaced, fN = PlaceClusteredFeature(farPlots, falloutType, cfg.falloutPlayableFarPct, "Wasteland Far Fallout");
	print("Wasteland fallout barrier:", bPlaced, "/", bN, " near:", nPlaced, "/", nN, " far:", fPlaced, "/", fN);
end
------------------------------------------------------------------------------
function AddWetlandBarrierFeatures()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local iW, iH = Map.GetGridSize();
	local barrierCol = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		barrierCol[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local marshPlots = {};
	local coverPlots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if barrierCol[x] == true and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE
					and plot:GetResourceType(-1) == -1 then
					if plot:GetPlotType() == PlotTypes.PLOT_LAND then
						table.insert(marshPlots, plot);
					end
					table.insert(coverPlots, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local mPlaced, mN = PlaceClusteredFeature(marshPlots, FeatureTypes.FEATURE_MARSH, cfg.marshBarrierPct, "Wetland Barrier Marsh");
	local junglePlots = {};
	local i = 1;
	while i <= #coverPlots do
		if coverPlots[i]:GetFeatureType() == FeatureTypes.NO_FEATURE then
			table.insert(junglePlots, coverPlots[i]);
		end
		i = i + 1;
	end
	local jPlaced, jN = PlaceClusteredFeature(junglePlots, FeatureTypes.FEATURE_JUNGLE, cfg.jungleBarrierPct, "Wetland Barrier Jungle");
	local ji = 1;
	while ji <= #coverPlots do
		if coverPlots[ji]:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
			coverPlots[ji]:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
		end
		ji = ji + 1;
	end
	local forestPlots = {};
	i = 1;
	while i <= #coverPlots do
		if coverPlots[i]:GetFeatureType() == FeatureTypes.NO_FEATURE then
			table.insert(forestPlots, coverPlots[i]);
		end
		i = i + 1;
	end
	local fPlaced, fN = PlaceClusteredFeature(forestPlots, FeatureTypes.FEATURE_FOREST, cfg.forestBarrierPct, "Wetland Barrier Forest");
	print("Wetland barrier marsh:", mPlaced, "/", mN, " jungle:", jPlaced, "/", jN, " forest:", fPlaced, "/", fN);
end
------------------------------------------------------------------------------
function StripBarrierResources()
	local cfg = GetBarrierConfig();
	if cfg == nil then
		return
	end
	local oilID = GameInfoTypes["RESOURCE_OIL"];
	local alumID = GameInfoTypes["RESOURCE_ALUMINUM"];
	local uranID = GameInfoTypes["RESOURCE_URANIUM"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local cols = GetSnowWrapColumns(iW, y);
		local ci = 1;
		while ci <= #cols do
			local x = cols[ci];
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if res ~= -1 then
					local strip = true;
					if cfg.kind == "peaks" then
						strip = false;
						local info = GameInfo.Resources[res];
						if info ~= nil then
							if info.ResourceClassType == "RESOURCECLASS_BONUS" or info.ResourceClassType == "RESOURCECLASS_LUXURY" then
								strip = true;
							end
						end
						if res == horseID or res == ironID then
							strip = true;
						end
					elseif res == oilID or res == alumID or res == uranID then
						strip = false;
					end
					if strip then
						plot:SetResourceType(-1);
						n = n + 1;
					end
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	if IsBramble() then
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if TongueIsBarrierPlot(x, y) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil then
						local res = plot:GetResourceType(-1);
						if res ~= -1 and res ~= oilID and res ~= alumID and res ~= uranID then
							plot:SetResourceType(-1);
							n = n + 1;
						end
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
	end
	print("Barrier resources stripped:", n);
end
------------------------------------------------------------------------------
-- True final word on "no resource ever on the Bramble separator" -- see the
-- call site's comment for why StripBarrierResources' own Bramble handling
-- (much earlier) isn't enough on its own.
function StripBrambleSeparatorResources()
	if IsBramble() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local mirrored = (DEF_MIRRORED == 1);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = brambleLo[y];
		while x <= brambleHi[y] do
			if MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetResourceType(-1) ~= -1 then
					plot:SetResourceType(-1);
					n = n + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Bramble separator resources stripped (final pass):", n);
end
------------------------------------------------------------------------------
function StripOasisBarrierForests()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "desert" then
		return
	end
	local deerID = GameInfoTypes["RESOURCE_DEER"];
	local furID = GameInfoTypes["RESOURCE_FUR"];
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] == true then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST then
					local res = plot:GetResourceType(-1);
					local keep = false;
					if deerID ~= nil and res == deerID then
						keep = true;
					elseif furID ~= nil and res == furID then
						keep = true;
					end
					if keep == false then
						plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
						n = n + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Oasis barrier forests stripped:", n);
end
------------------------------------------------------------------------------
function GetWestTundraFrontBands(iW)
	local bands = {};
	local wrapN, centerN = ResolveSnowWrapWidths();
	local mid = math.floor(iW / 2);
	local blocked = {};
	local snow = GetSnowWrapColumns(iW);
	local i = 1;
	while i <= #snow do
		blocked[snow[i]] = true;
		i = i + 1;
	end
	local tundra = GetSnowWrapTundraColumns(iW);
	i = 1;
	while i <= #tundra do
		blocked[tundra[i]] = true;
		i = i + 1;
	end
	if centerN > 0 then
		local tundraX = mid - centerN / 2 - 1;
		local cols = {};
		local c1 = tundraX - 1;
		local c2 = tundraX - 2;
		if c1 ~= nil and blocked[c1] ~= true and c1 >= 0 and c1 < iW then
			table.insert(cols, c1);
		end
		if c2 ~= nil and blocked[c2] ~= true and c2 >= 0 and c2 < iW then
			table.insert(cols, c2);
		end
		if #cols > 0 then
			table.insert(bands, cols);
		end
	end
	if wrapN > 0 then
		local tundraX = wrapN / 2;
		local cols = {};
		local c1 = tundraX + 1;
		local c2 = tundraX + 2;
		if c1 ~= nil and blocked[c1] ~= true and c1 >= 0 and c1 < iW then
			table.insert(cols, c1);
		end
		if c2 ~= nil and blocked[c2] ~= true and c2 >= 0 and c2 < iW then
			table.insert(cols, c2);
		end
		if #cols > 0 then
			table.insert(bands, cols);
		end
	end
	return bands;
end
------------------------------------------------------------------------------
function CollectTundraFrontPlots(cols, iW, iH)
	local plots = {};
	local mirrored = (DEF_MIRRORED == 1);
	local y = 0;
	while y < iH do
		local ci = 1;
		while ci <= #cols do
			local x = cols[ci];
			if x >= 0 and x < iW and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and PlotIsMajorStart(plot) == false
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetResourceType(-1) == -1 then
					table.insert(plots, plot);
				end
			end
			ci = ci + 1;
		end
		y = y + 1;
	end
	return plots;
end
------------------------------------------------------------------------------
function PlaceDesertTundraFrontResources()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind == "peaks" or IsTiltedMirrorAxis() then
		return
	end
	local iW, iH = Map.GetGridSize();
	local bands = GetWestTundraFrontBands(iW);
	if #bands < 1 then
		return
	end
	local mirrored = (DEF_MIRRORED == 1);
	local unusedLux = {};
	local allPlots = {};
	local bi = 1;
	while bi <= #bands do
		local plots = CollectTundraFrontPlots(bands[bi], iW, iH);
		local p = 1;
		while p <= #plots do
			table.insert(allPlots, plots[p]);
			p = p + 1;
		end
		bi = bi + 1;
	end
	if cfg.kind == "desert" then
		local placedLux = {};
		local y = 0;
		while y < iH do
			local x = 0;
			local maxX = iW - 1;
			if mirrored then
				maxX = math.floor(iW / 2);
			end
			while x <= maxX do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local res = plot:GetResourceType(-1);
					if res ~= nil and res ~= -1 then
						placedLux[res] = true;
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		for res in GameInfo.Resources() do
			if res.Happiness ~= nil and res.Happiness > 0 and placedLux[res.ID] ~= true then
				table.insert(unusedLux, res.ID);
			end
		end
		unusedLux = GetShuffledCopyOfTable(unusedLux);
	end
	local nLuxWant = 0;
	local luxPlaced = 0;
	if cfg.kind == "desert" then
		nLuxWant = Map.Rand(3, "Desert Front Unique Lux Count");
		local shuffledPlots = GetShuffledCopyOfTable(allPlots);
		local luxI = 1;
		while luxI <= #unusedLux and luxPlaced < nLuxWant do
			local luxID = unusedLux[luxI];
			local p = 1;
			while p <= #shuffledPlots do
				local plot = shuffledPlots[p];
				if plot:GetResourceType(-1) == -1 and plot:CanHaveResource(luxID) then
					plot:SetResourceType(luxID, 1);
					luxPlaced = luxPlaced + 1;
					break
				end
				p = p + 1;
			end
			luxI = luxI + 1;
		end
	end
	local bonusIDs = {};
	for res in GameInfo.Resources() do
		local class = res.ResourceClassType;
		if class == "RESOURCECLASS_BONUS" or class == "RESOURCECLASS_RUSH" or class == "RESOURCECLASS_MODERN" then
			if res.Type ~= "RESOURCE_FISH" then
				table.insert(bonusIDs, res.ID);
			end
		end
	end
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	local oilID = GameInfoTypes["RESOURCE_OIL"];
	local coalID = GameInfoTypes["RESOURCE_COAL"];
	local alumID = GameInfoTypes["RESOURCE_ALUMINUM"];
	local uranID = GameInfoTypes["RESOURCE_URANIUM"];
	local bonusPlaced = 0;
	bi = 1;
	while bi <= #bands do
		local plots = CollectTundraFrontPlots(bands[bi], iW, iH);
		plots = GetShuffledCopyOfTable(plots);
		local nWant = 8 + Map.Rand(5, "Front Bonus Count");
		local placed = 0;
		local p = 1;
		while p <= #plots and placed < nWant do
			local plot = plots[p];
			local nFit = 0;
			local fit = {};
			local k = 1;
			while k <= #bonusIDs do
				if bonusIDs[k] ~= nil and plot:CanHaveResource(bonusIDs[k]) then
					nFit = nFit + 1;
					fit[nFit] = bonusIDs[k];
				end
				k = k + 1;
			end
			if nFit > 0 then
				local pick = fit[Map.Rand(nFit, "Front Bonus Pick") + 1];
				local amt = 1;
				if pick == ironID or pick == horseID or pick == oilID or pick == coalID or pick == alumID or pick == uranID then
					amt = 2;
				end
				plot:SetResourceType(pick, amt);
				placed = placed + 1;
				bonusPlaced = bonusPlaced + 1;
			end
			p = p + 1;
		end
		bi = bi + 1;
	end
	print("Front band resources: lux=", luxPlaced, "/", nLuxWant, " bonus=", bonusPlaced, " bands=", #bands);
end
------------------------------------------------------------------------------
function PlaceMurkTundraLakeFish()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	if #murkTundraLakeTiles < 1 then
		return
	end
	local fishID = GameInfoTypes["RESOURCE_FISH"];
	if fishID == nil then
		return
	end
	local iW = Map.GetGridSize();
	local seen = {};
	local placed = 0;
	local lakes = 0;
	local i = 1;
	while i <= #murkTundraLakeTiles do
		local seed = murkTundraLakeTiles[i];
		local si = seed:GetY() * iW + seed:GetX() + 1;
		if seen[si] ~= true then
			local tiles = {};
			local q = {seed};
			local qi = 1;
			seen[si] = true;
			table.insert(tiles, seed);
			while qi <= #q do
				local p = q[qi];
				qi = qi + 1;
				local d = 0;
				while d < DirectionTypes.NUM_DIRECTION_TYPES do
					local adj = PlotDirNoXWrap(p:GetX(), p:GetY(), d);
					if adj ~= nil and adj:IsWater() then
						local ai = adj:GetY() * iW + adj:GetX() + 1;
						if seen[ai] ~= true then
							seen[ai] = true;
							table.insert(q, adj);
							table.insert(tiles, adj);
						end
					end
					d = d + 1;
				end
			end
			lakes = lakes + 1;
			local hasFish = false;
			local cands = {};
			local ti = 1;
			while ti <= #tiles do
				local p = tiles[ti];
				local res = p:GetResourceType(-1);
				if res == fishID then
					hasFish = true;
				elseif res == -1 and p:GetFeatureType() ~= FeatureTypes.FEATURE_ICE then
					table.insert(cands, p);
				end
				ti = ti + 1;
			end
			if hasFish == false and #cands > 0 and Map.Rand(100, "Mire Tundra Lake Fish") < 82 then
				local pick = cands[1 + Map.Rand(#cands, "Mire Tundra Lake Fish Tile")];
				pick:SetResourceType(fishID, 1);
				placed = placed + 1;
			end
		end
		i = i + 1;
	end
	print("Murk tundra lake fish: lakes=", lakes, " added=", placed);
end
------------------------------------------------------------------------------
function PlaceBrambleSaltFish()
	if IsBramble() == false then
		return
	end
	local fishID = GameInfoTypes["RESOURCE_FISH"];
	if fishID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW * 0.5);
	end
	local water = {};
	local nHave = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:IsWater() and WaterAllowedAtXY(x, y) then
				local res = plot:GetResourceType(-1);
				if res == fishID then
					nHave = nHave + 1;
				elseif res == -1 and plot:CanHaveResource(fishID) then
					table.insert(water, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nTiles = nHave + #water;
	local want = math.floor(nTiles * 0.28 + 0.5);
	if want < 4 then
		want = 4;
	end
	if want > 8 then
		want = 8;
	end
	water = GetShuffledCopyOfTable(water);
	local placed = 0;
	local i = 1;
	while nHave < want and i <= #water do
		water[i]:SetResourceType(fishID, 1);
		nHave = nHave + 1;
		placed = placed + 1;
		i = i + 1;
	end
	print("Bramble salt fish:", nHave, "/", nTiles, " added", placed);
end
------------------------------------------------------------------------------
function PlaceMurkTundraSheepStone()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local sheepID = GameInfoTypes["RESOURCE_SHEEP"];
	local stoneID = GameInfoTypes["RESOURCE_STONE"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	if sheepID == nil or stoneID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local hillPlots = {};
	local flatPlots = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local i = y * iW + x + 1;
			if mireBand[i] == 1 and skip[x] ~= true and ((not mirrored) or (x <= iW * 0.5)) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetResourceType(-1) == -1
					and plot:GetFeatureType() == FeatureTypes.NO_FEATURE
					and plot:GetTerrainType() ~= TerrainTypes.TERRAIN_SNOW then
					if plot:GetPlotType() == PlotTypes.PLOT_HILLS then
						table.insert(hillPlots, plot);
					elseif plot:GetPlotType() == PlotTypes.PLOT_LAND then
						table.insert(flatPlots, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	hillPlots = GetShuffledCopyOfTable(hillPlots);
	flatPlots = GetShuffledCopyOfTable(flatPlots);
	local horseN = 0;
	if horseID ~= nil then
		local nHorse = math.floor(#flatPlots * 0.04 + 0.5);
		if nHorse < 2 then
			nHorse = 2;
		end
		if nHorse > 5 then
			nHorse = 5;
		end
		local hp = 1;
		while horseN < nHorse and hp <= #flatPlots do
			local plot = flatPlots[hp];
			if plot:GetResourceType(-1) == -1 and plot:GetPlotType() == PlotTypes.PLOT_LAND then
				plot:SetResourceType(horseID, 2);
				horseN = horseN + 1;
			end
			hp = hp + 1;
		end
	end
	local nSheep = math.floor(#hillPlots * 0.22 + 0.5);
	if nSheep < 2 then
		nSheep = 2;
	end
	local sheepN = 0;
	local hi = 1;
	while sheepN < nSheep and hi <= #hillPlots do
		if hillPlots[hi]:CanHaveResource(sheepID) then
			hillPlots[hi]:SetResourceType(sheepID, 1);
			sheepN = sheepN + 1;
		end
		hi = hi + 1;
	end
	local fi = 1;
	while sheepN < nSheep and fi <= #flatPlots do
		local plot = flatPlots[fi];
		if plot:GetResourceType(-1) == -1 then
			plot:SetPlotType(PlotTypes.PLOT_HILLS, false, false);
			if plot:CanHaveResource(sheepID) then
				plot:SetResourceType(sheepID, 1);
				sheepN = sheepN + 1;
			else
				plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
			end
		end
		fi = fi + 1;
	end
	local nStone = math.floor(#flatPlots * 0.05 + 0.5);
	local stoneN = 0;
	fi = 1;
	while stoneN < nStone and fi <= #flatPlots do
		local plot = flatPlots[fi];
		if plot:GetResourceType(-1) == -1 and plot:GetPlotType() == PlotTypes.PLOT_LAND and plot:CanHaveResource(stoneID) then
			plot:SetResourceType(stoneID, 1);
			stoneN = stoneN + 1;
		end
		fi = fi + 1;
	end
	print("Murk tundra extras sheep:", sheepN, " stone:", stoneN, " horse:", horseN);
end
------------------------------------------------------------------------------
function PlaceMurkWheatAndMarshStone()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local wheatID = GameInfoTypes["RESOURCE_WHEAT"];
	local stoneID = GameInfoTypes["RESOURCE_STONE"];
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nWheat = 0;
	local nStone = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetResourceType(-1) == -1 then
					if stoneID ~= nil and plot:GetFeatureType() == FeatureTypes.FEATURE_MARSH then
						if Map.Rand(100, "Murk Marsh Stone") < 6 then
							plot:SetResourceType(stoneID, 1);
							nStone = nStone + 1;
						end
					elseif wheatID ~= nil
						and plot:GetPlotType() == PlotTypes.PLOT_LAND
						and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
						and plot:IsRiver()
						and plot:GetFeatureType() ~= FeatureTypes.FEATURE_MARSH then
						if Map.Rand(100, "Murk Tundra Wheat") < 8 then
							plot:SetResourceType(wheatID, 1);
							nWheat = nWheat + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Murk tundra wheat:", nWheat, " marsh stone:", nStone);
end
------------------------------------------------------------------------------
function PlaceMurkSnowStoneIron()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wetland" then
		return
	end
	local stoneID = GameInfoTypes["RESOURCE_STONE"];
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	if stoneID == nil and ironID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nStone = 0;
	local nIron = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW
					and plot:GetResourceType(-1) == -1 then
					local pt = Map.Rand(100, "Murk Snow Res");
					if stoneID ~= nil and pt < 5 then
						plot:SetResourceType(stoneID, 1);
						nStone = nStone + 1;
					elseif ironID ~= nil and pt < 9 then
						plot:SetResourceType(ironID, 2);
						nIron = nIron + 1;
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Murk snow stone:", nStone, " iron:", nIron);
end
------------------------------------------------------------------------------
function PlaceFrostySnowStoneIron()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "frosty" then
		return
	end
	local sheepID = GameInfoTypes["RESOURCE_SHEEP"];
	local stoneID = GameInfoTypes["RESOURCE_STONE"];
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local nSheep = 0;
	local nStone = 0;
	local nIron = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW
					and sheepID ~= nil
					and plot:GetResourceType(-1) == sheepID then
					plot:SetResourceType(-1);
					nSheep = nSheep + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW
					and plot:GetResourceType(-1) == -1 then
					local pt = plot:GetPlotType();
					local roll = Map.Rand(100, "Frosty Snow Res");
					if pt == PlotTypes.PLOT_HILLS then
						if stoneID ~= nil and roll < 10 then
							plot:SetResourceType(stoneID, 1);
							nStone = nStone + 1;
						elseif ironID ~= nil and roll < 17 then
							plot:SetResourceType(ironID, 2);
							nIron = nIron + 1;
						end
					else
						if stoneID ~= nil and roll < 5 then
							plot:SetResourceType(stoneID, 1);
							nStone = nStone + 1;
						elseif ironID ~= nil and roll < 8 then
							plot:SetResourceType(ironID, 2);
							nIron = nIron + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Frosty snow sheep stripped:", nSheep, " stone:", nStone, " iron:", nIron);
end
------------------------------------------------------------------------------
function PlacePeaksPlainsCattle()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "peaks" then
		return
	end
	local cowID = GameInfoTypes["RESOURCE_COW"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	if cowID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local snowCols = GetSnowWrapColumns(iW);
	local sci = 1;
	while sci <= #snowCols do
		skip[snowCols[sci]] = true;
		sci = sci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local nHorse = 0;
	local plains = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and plot:IsWater() == false then
					if horseID ~= nil and plot:GetResourceType(-1) == horseID then
						nHorse = nHorse + 1;
					end
					if plot:GetPlotType() == PlotTypes.PLOT_LAND
						and plot:GetTerrainType() == TerrainTypes.TERRAIN_PLAINS
						and plot:GetFeatureType() == FeatureTypes.NO_FEATURE
						and plot:GetResourceType(-1) == -1 then
						table.insert(plains, plot);
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local nWant = math.floor(nHorse * 0.15 / 0.85 + 0.5);
	if nWant < 1 or #plains < 1 then
		print("Peaks plains cattle:", 0, " horses:", nHorse);
		return
	end
	plains = GetShuffledCopyOfTable(plains);
	local n = 0;
	local i = 1;
	while n < nWant and i <= #plains do
		if plains[i]:GetResourceType(-1) == -1 then
			plains[i]:SetResourceType(cowID, 1);
			n = n + 1;
		end
		i = i + 1;
	end
	print("Peaks plains cattle:", n, "/", nWant, " horses:", nHorse);
end
------------------------------------------------------------------------------
function StripIllegalMountainResources()
	local iW, iH = Map.GetGridSize();
	local n = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil
				and plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN
				and plot:GetResourceType(-1) ~= -1
				and PlotHasNaturalWonder(plot) ~= true then
				plot:SetResourceType(-1);
				n = n + 1;
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Stripped mountain resources:", n);
end
-------------------------------------------------------------------------------
-- Late safety net (pre-mirror): a handful of barrier-relief passes (snow
-- peak/hill carving, mountain capping, etc.) run after AddFeatures and
-- mutate plot type/terrain without checking for a feature that's no longer
-- legal there afterward -- e.g. a marsh whose tile just became hills, or a
-- floodplains whose tile's terrain just got repainted away from desert/
-- plains. Rather than chase every such upstream pass individually, just
-- verify every marsh/floodplains tile is still legal once everything else
-- is done and drop the ones that aren't. CanHaveFeature is the same check
-- the engine itself uses to place these, so a still-valid tile is untouched.
-- NOTE: CvPlot::canHaveFeature returns false unconditionally whenever the
-- plot already has ANY feature (checked before terrain legality), so it must
-- never be called while the feature-under-test is still set on the plot --
-- clear it first, then restore if the tile is still legal.
function StripInvalidWetFeatures()
	local nMarsh = 0;
	local nFlood = 0;
	for i, plot in Plots() do
		local feat = plot:GetFeatureType();
		if feat == FeatureTypes.FEATURE_MARSH then
			plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			if plot:CanHaveFeature(FeatureTypes.FEATURE_MARSH) then
				plot:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1);
			else
				nMarsh = nMarsh + 1;
			end
		elseif feat == FeatureTypes.FEATURE_FLOOD_PLAINS then
			plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1);
			if plot:CanHaveFeature(FeatureTypes.FEATURE_FLOOD_PLAINS) then
				plot:SetFeatureType(FeatureTypes.FEATURE_FLOOD_PLAINS, -1);
			else
				nFlood = nFlood + 1;
			end
		end
	end
	print("Invalid wet features stripped: marsh=", nMarsh, " floodplains=", nFlood);
end
-------------------------------------------------------------------------------
function PlaceWastelandTundraWheatSheep()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "wasteland" then
		return
	end
	local wheatID = GameInfoTypes["RESOURCE_WHEAT"];
	local sheepID = GameInfoTypes["RESOURCE_SHEEP"];
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local nWheat = 0;
	local nSheep = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and plot:IsWater() == false
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetTerrainType() == TerrainTypes.TERRAIN_TUNDRA
					and plot:GetResourceType(-1) == -1 then
					local placed = false;
					if wheatID ~= nil and plot:IsRiver() then
						if Map.Rand(100, "Wasteland Tundra Wheat") < 10 then
							plot:SetResourceType(wheatID, 1);
							nWheat = nWheat + 1;
							placed = true;
						end
					end
					if placed == false and sheepID ~= nil then
						if Map.Rand(100, "Wasteland Tundra Sheep") < 4 then
							plot:SetResourceType(sheepID, 1);
							nSheep = nSheep + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("Wasteland tundra wheat:", nWheat, " sheep:", nSheep);
end
------------------------------------------------------------------------------
function PlaceDesertMainlandResourceBoost()
	local cfg = GetBarrierConfig();
	if cfg == nil or cfg.kind ~= "desert" then
		return
	end
	local ids = {
		GameInfoTypes["RESOURCE_BANANA"],
		GameInfoTypes["RESOURCE_WHEAT"],
		GameInfoTypes["RESOURCE_COW"],
		GameInfoTypes["RESOURCE_SHEEP"],
		GameInfoTypes["RESOURCE_DEER"],
		GameInfoTypes["RESOURCE_STONE"],
		GameInfoTypes["RESOURCE_HORSE"],
		GameInfoTypes["RESOURCE_IRON"],
		GameInfoTypes["RESOURCE_INCENSE"],
		GameInfoTypes["RESOURCE_GOLD"],
		GameInfoTypes["RESOURCE_SILVER"],
		GameInfoTypes["RESOURCE_GEMS"],
		GameInfoTypes["RESOURCE_COPPER"],
		GameInfoTypes["RESOURCE_SALT"],
		GameInfoTypes["RESOURCE_OIL"],
	};
	local iW, iH = Map.GetGridSize();
	local skip = {};
	local cols = GetSnowWrapColumns(iW);
	local ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	cols = GetSnowWrapTundraColumns(iW);
	ci = 1;
	while ci <= #cols do
		skip[cols[ci]] = true;
		ci = ci + 1;
	end
	local mirrored = (DEF_MIRRORED == 1);
	local eligible = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and PlotIsMajorStart(plot) == false
					and plot:IsWater() == false
					and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN
					and plot:GetResourceType(-1) == -1 then
					table.insert(eligible, plot);
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local shuffled = GetShuffledCopyOfTable(eligible);
	local n = #shuffled;
	local target = math.floor(n * 0.09 + 0.5);
	local placed = 0;
	local i = 1;
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	local oilID = GameInfoTypes["RESOURCE_OIL"];
	while i <= n and placed < target do
		local plot = shuffled[i];
		local nFit = 0;
		local fit = {};
		local k = 1;
		while k <= #ids do
			if ids[k] ~= nil and plot:CanHaveResource(ids[k]) then
				nFit = nFit + 1;
				fit[nFit] = ids[k];
			end
			k = k + 1;
		end
		if nFit > 0 then
			local pick = fit[Map.Rand(nFit, "Desert Resource Boost") + 1];
			local amt = 1;
			if pick == ironID or pick == horseID or pick == oilID then
				amt = 2;
			end
			plot:SetResourceType(pick, amt);
			placed = placed + 1;
		end
		i = i + 1;
	end
	print("Desert mainland resource boost:", placed, "/", n);
end
------------------------------------------------------------------------------
function PlaceOasisFrontColumnExtras()
	if IsOasisClimate() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local cols = OasisFrontMostColumns(iW, iH);
	if #cols < 1 then
		return
	end
	local inFront = {};
	local ci = 1;
	while ci <= #cols do
		inFront[cols[ci]] = true;
		ci = ci + 1;
	end
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local ids = {
		GameInfoTypes["RESOURCE_BANANA"],
		GameInfoTypes["RESOURCE_WHEAT"],
		GameInfoTypes["RESOURCE_COW"],
		GameInfoTypes["RESOURCE_SHEEP"],
		GameInfoTypes["RESOURCE_DEER"],
		GameInfoTypes["RESOURCE_STONE"],
		GameInfoTypes["RESOURCE_HORSE"],
		GameInfoTypes["RESOURCE_IRON"],
		GameInfoTypes["RESOURCE_INCENSE"],
		GameInfoTypes["RESOURCE_GOLD"],
		GameInfoTypes["RESOURCE_SILVER"],
		GameInfoTypes["RESOURCE_GEMS"],
		GameInfoTypes["RESOURCE_COPPER"],
		GameInfoTypes["RESOURCE_SALT"],
		GameInfoTypes["RESOURCE_OIL"],
	};
	local ironID = GameInfoTypes["RESOURCE_IRON"];
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	local oilID = GameInfoTypes["RESOURCE_OIL"];
	local deerID = GameInfoTypes["RESOURCE_DEER"];
	local furID = GameInfoTypes["RESOURCE_FUR"];
	local empty = {};
	local forestCands = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if inFront[x] == true and skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil and PlotIsMajorStart(plot) == false and plot:IsWater() == false and plot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
					if PlotHasNaturalWonder(plot) == false then
						if plot:GetResourceType(-1) == -1 then
							table.insert(empty, plot);
						end
						local ter = plot:GetTerrainType();
						if ter == TerrainTypes.TERRAIN_TUNDRA or ter == TerrainTypes.TERRAIN_PLAINS then
							if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
								table.insert(forestCands, plot);
							end
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local resPlaced = 0;
	if #empty > 0 then
		local shuffled = GetShuffledCopyOfTable(empty);
		local target = math.floor(#shuffled * 0.12 + 0.5);
		if target < 1 and #shuffled > 0 then
			target = 1;
		end
		local i = 1;
		while i <= #shuffled and resPlaced < target do
			local plot = shuffled[i];
			local nFit = 0;
			local fit = {};
			local k = 1;
			while k <= #ids do
				if ids[k] ~= nil and plot:CanHaveResource(ids[k]) then
					nFit = nFit + 1;
					fit[nFit] = ids[k];
				end
				k = k + 1;
			end
			if nFit > 0 then
				local pick = fit[Map.Rand(nFit, "Oasis front res") + 1];
				local amt = 1;
				if pick == ironID or pick == horseID or pick == oilID then
					amt = 2;
				end
				plot:SetResourceType(pick, amt);
				resPlaced = resPlaced + 1;
			end
			i = i + 1;
		end
	end
	local forests = 0;
	local fi = 1;
	while fi <= #forestCands do
		local plot = forestCands[fi];
		if plot:GetFeatureType() == FeatureTypes.NO_FEATURE then
			local res = plot:GetResourceType(-1);
			local resOk = true;
			if res ~= nil and res ~= -1 then
				resOk = false;
				if deerID ~= nil and res == deerID then
					resOk = true;
				elseif furID ~= nil and res == furID then
					resOk = true;
				end
			end
			if resOk and Map.Rand(100, "Oasis front forest") < 15 then
				plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1);
				forests = forests + 1;
			end
		end
		fi = fi + 1;
	end
	print("Oasis front columns extras: res", resPlaced, "forest", forests, "cols", #cols);
end
------------------------------------------------------------------------------
function PlaceOasisForcedHorses()
	if IsOasisClimate() == false then
		return
	end
	local horseID = GameInfoTypes["RESOURCE_HORSE"];
	if horseID == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local skip = FillMireSkip(iW);
	local mirrored = (DEF_MIRRORED == 1);
	local startSkip = {};
	local pi = 0;
	while pi < GameDefines.MAX_MAJOR_CIVS do
		local player = Players[pi];
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil then
				startSkip[sp:GetY() * iW + sp:GetX()] = true;
			end
		end
		pi = pi + 1;
	end
	local cands = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			if skip[x] ~= true and MirrorOwnsPlot(x, y, mirrored, iW) then
				local plot = Map.GetPlot(x, y);
				if plot ~= nil
					and startSkip[y * iW + x] ~= true
					and plot:GetPlotType() == PlotTypes.PLOT_LAND
					and plot:GetResourceType(-1) == -1 then
					local t = plot:GetTerrainType();
					if t == TerrainTypes.TERRAIN_GRASS or t == TerrainTypes.TERRAIN_PLAINS then
						if plot:CanHaveResource(horseID) then
							table.insert(cands, plot);
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local want = Map.Rand(4, "Oasis extra horses");
	cands = GetShuffledCopyOfTable(cands);
	local n = 0;
	local i = 1;
	while n < want and i <= #cands do
		cands[i]:SetResourceType(horseID, 2);
		n = n + 1;
		i = i + 1;
	end
	print("Oasis extra horses:", n, "/", want, " cands", #cands);
end
------------------------------------------------------------------------------
function FixNorthUniqueLuxuries()
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW * 0.5);
	end
	local northY = iH - 5;
	if northY < 0 then
		northY = 0;
	end
	local function isLux(res)
		if res == nil or res == -1 then
			return false
		end
		return Game.GetResourceUsageType(res) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY;
	end
	local function gather()
		local counts = {};
		local plots = {};
		local y = 0;
		while y < iH do
			local x = 0;
			while x <= maxX do
				local plot = Map.GetPlot(x, y);
				if plot ~= nil then
					local res = plot:GetResourceType(-1);
					if isLux(res) then
						if counts[res] == nil then
							counts[res] = 0;
							plots[res] = {};
						end
						counts[res] = counts[res] + 1;
						table.insert(plots[res], plot);
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
		return counts, plots;
	end
	local nFix = 0;
	local y = northY;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local u = plot:GetResourceType(-1);
				if isLux(u) then
					local counts, plots = gather();
					if counts[u] == 1 then
						local uWater = plot:IsWater();
						local done = false;
						local resID, list;
						for resID, list in pairs(plots) do
							if done == false and resID ~= u and counts[resID] ~= nil and counts[resID] >= 2 then
								local pi = 1;
								while pi <= #list do
									local p = list[pi];
									if p:GetY() < northY and p:IsWater() == uWater and p:CanHaveResource(u) then
										p:SetResourceType(u, 1);
										done = true;
										break
									end
									pi = pi + 1;
								end
							end
						end
						if done == false then
							for resID, list in pairs(plots) do
								if done == false and resID ~= u and counts[resID] ~= nil and counts[resID] >= 1 then
									local sameDomain = false;
									local pi = 1;
									while pi <= #list do
										if list[pi]:IsWater() == uWater then
											sameDomain = true;
											break
										end
										pi = pi + 1;
									end
									if sameDomain and plot:CanHaveResource(resID) then
										plot:SetResourceType(resID, 1);
										done = true;
									end
								end
							end
						end
						if done then
							nFix = nFix + 1;
						end
					end
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	print("North unique lux fixes:", nFix);
end
------------------------------------------------------------------------------
function getMirroredPlot(plot)
	local iW, iH = Map.GetGridSize();
	local x = iW - plot:GetX() - 1;
	local y = iH - plot:GetY() - 1;
	local mirrorPlot = Map.GetPlot(x, y);
	return mirrorPlot;
end
------------------------------------------------------------------------------
function isValidPlayer(pPlayer)
	return  pPlayer ~= nil and pPlayer:GetStartingPlot() ~= nil and pPlayer:IsAlive();
end
------------------------------------------------------------------------------
function ClearRiversNearBarrier()
	local iW, iH = Map.GetGridSize()
	for y = 0, iH - 1 do
		local snowCols = GetSnowWrapColumns(iW, y);
		for _, x in ipairs(snowCols) do
			local plot = Map.GetPlot(x, y)
			if plot ~= nil then
				plot:SetWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
				plot:SetNWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
				plot:SetNEOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
			end
		end
	end
	if IsBramble() then
		local y = 0;
		while y < iH do
			local x = 0;
			while x < iW do
				if TongueIsBarrierPlot(x, y) then
					local plot = Map.GetPlot(x, y);
					if plot ~= nil then
						plot:SetWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
						plot:SetNWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
						plot:SetNEOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
					end
				end
				x = x + 1;
			end
			y = y + 1;
		end
	end
end
------------------------------------------------------------------------------
function MirrorPlotsAfterResourcePlacement()
	------------------------------------------------------------------------------
	----------------------- INCLUDE getMirroredPlot()-----------------------------
	----------------- Copyright 2010  (c)  Leszek Deska --------------------------
	------------------------------------------------------------------------------
	-- mirrorize plot types, terrain, resource, natural wonders, ruins (ruins doesn't work)
	local iW, iH = Map.GetGridSize()
	print("iW/iH=",iW, iH)
	for x = 0, iW * 0.5 do
		for y = 0, iH - 1 do
			if( iW-x-y%2 ~= x ) then
				local plot = Map.GetPlot(x, y);
				local mirrorPlot = getMirroredPlot(plot);
				local skipDest = false;
				if plot ~= nil and mirrorPlot ~= nil then
					skipDest = TiltedSkipMirrorDest(x, y, mirrorPlot:GetX(), mirrorPlot:GetY());
				end
				if skipDest == false and plot ~= nil and mirrorPlot ~= nil then
				local plotType = plot:GetPlotType();
				local terrainType = plot:GetTerrainType();
				local featureType = plot:GetFeatureType();
				local improvementType = plot:GetImprovementType();
				local resourceType = plot:GetResourceType(-1)
				mirrorPlot:SetPlotType(plotType,false,false)
				mirrorPlot:SetTerrainType(terrainType,false,false)
				mirrorPlot:SetFeatureType(featureType, -1)
				mirrorPlot:SetResourceType(resourceType,plot:GetNumResource())
				mirrorPlot:SetImprovementType(improvementType)
				end
			end
		end
	end
	TiltedCopyHomePastMidToPair(true);
	-- rivers
	-- mirrorize rivers
	--rivers
	for x = math.floor(iW / 2)+1, iW - 1 do
		for y = 0, iH - 1 do
			local plot = Map.GetPlot(x, y)
			plot:SetWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
			plot:SetNWOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
			plot:SetNEOfRiver(false,FlowDirectionTypes.NO_FLOWDIRECTION)
		end
	end
	for y = 0, iH - 1 do
		for x = 0, iW * 0.5 do
		    if ( x < (iW/2 + 1) ) then
            	local plot = Map.GetPlot(x, y);
				if ( plot:IsWOfRiver() ) then
					local mirrorPlot = getMirroredPlot(plot);
					mirrorPlot = PlotDirNoXWrap(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
					if mirrorPlot ~= nil then
						local dir = FlowDirectionTypes.FLOWDIRECTION_NORTH;
						if( plot:GetRiverEFlowDirection() == FlowDirectionTypes.FLOWDIRECTION_NORTH ) then
							dir = FlowDirectionTypes.FLOWDIRECTION_SOUTH;
						end
						mirrorPlot:SetWOfRiver(true, dir);
					end
				end
				if ( plot:IsNWOfRiver() ) then
					local mirrorPlot = getMirroredPlot(plot);
					mirrorPlot = PlotDirNoXWrap(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
					if mirrorPlot ~= nil then
						local dir = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST;
						if( plot:GetRiverSEFlowDirection() == FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST) then
							dir = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST;
						end;
						mirrorPlot:SetNWOfRiver(true, dir);
					end
				end
				if ( plot:IsNEOfRiver() ) then
					local mirrorPlot = getMirroredPlot(plot);
					mirrorPlot = PlotDirNoXWrap(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
					if mirrorPlot ~= nil then
						local dir = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST;
						if( plot:GetRiverSWFlowDirection() == FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST) then
							dir = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST;
						end;
						mirrorPlot:SetNEOfRiver(true, dir);
					end
				end
			end
		end
	end
	-- mirrorize starting positions
	local playerStartPlot;
	local searchMode = 0;
	for i = 0, GameDefines.MAX_MAJOR_CIVS + GameDefines.MAX_MINOR_CIVS - 1 do
		local player = Players[i];
		if (isValidPlayer(player)) then
			if player:IsEverAlive() then
				if( searchMode == 0 ) then
					searchMode = 1;
					player = Players[i];
					playerStartPlot = player:GetStartingPlot();
				else
					searchMode = 0;
					player = Players[i];
					player:SetStartingPlot(getMirroredPlot(playerStartPlot));
				end
			end
		end
	end
	Map:RecalculateAreas();
	Game.SetOption(1, true);
end
------------------------------------------------------------------------------
function StartPlotSystem()
	WeeveeDbg("StartPlotSystem");
	local res = DEF_RESOURCES;
	if res == 9 then
		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
	end

	WeeveeDbg("Create start db");
	local start_plot_database = AssignStartingPlots.Create()
	WeeveeDbg("GenerateRegions");
	start_plot_database:GenerateRegions()
	WeeveeDbg("SetDivide");
	SetDivide()
	WeeveeDbg("ChooseLocations");
	start_plot_database:ChooseLocations()
	WeeveeDbg("ChooseLocations done");
	WeeveeDbgCall("PeakEnsureStartHills", function() PeakEnsureStartHills(start_plot_database) end);
	WeeveeDbgCall("ClampAspStartsOffEdges", function() ClampAspStartsOffEdges(start_plot_database) end);
	WeeveeDbgCall("OasisSpreadStarts", function() OasisSpreadStarts(start_plot_database) end);
	WeeveeDbgCall("EnforceMinStartDistance", function() EnforceMinStartDistance(start_plot_database, 7) end);
	WeeveeDbg("BalanceAndAssign");
	start_plot_database:BalanceAndAssign()
	WeeveeDbg("BalanceAndAssign done");

	-- Stabilize final player start positions before natural wonders stamp
	-- their exclusion ripple, so a wonder never ends up "safe" from a start
	-- that later gets relocated by these same two calls (they also run again
	-- at the very end as a safety net for anything terrain work shifts later).
	WeeveeDbgCall("ClampPlayerStartsOffEdges", ClampPlayerStartsOffEdges);
	WeeveeDbgCall("NudgePlayerStartsMinDist", function() NudgePlayerStartsMinDist(7) end);

	--print("Placing Natural Wonders.");
	--start_plot_database:PlaceNaturalWonders()

	print("Placing Natural Wonders.");
	local wonders = DEF_NATURAL_WONDERS
	if wonders == 16 then
		wonders = 2 + Map.Rand(4, "Number of Wonders 2-5 - Lua");
	elseif wonders == 14 then
		wonders = Map.Rand(13, "Number of Wonders To Spawn - Lua");
	else
		wonders = wonders - 1;
	end

	print("########## Wonders ##########");
	print("Natural Wonders To Place: ", wonders);

	local wonderargs = {
		wonderamt = wonders,
	};

	WeeveeDbg("PlaceNaturalWonders");
	WeeveeDbgCall("PlaceNaturalWonders", function() start_plot_database:PlaceNaturalWonders(wonderargs) end);
	WeeveeDbgCall("StripSeparatorNaturalWonders", StripSeparatorNaturalWonders);
	WeeveeDbgCall("AuditFrontMountainGaps", AuditFrontMountainGaps);
	WeeveeDbgCall("MaybePlaceFujiHorses", function() MaybePlaceFujiHorses(start_plot_database) end);
	WeeveeDbgCall("EnsureStartHillsFloor", EnsureStartHillsFloor);
	WeeveeDbg("PlaceResources");
	WeeveeDbgCall("AddWastelandWaterLayout", AddWastelandWaterLayout);
	WeeveeDbgCall("FixWastelandFloodPlains", FixWastelandFloodPlains);
	WeeveeDbgCall("AddWastelandTundraForests", AddWastelandTundraForests);
	WeeveeDbgCall("PlaceResourcesAndCityStates", function() start_plot_database:PlaceResourcesAndCityStates() end);
	WeeveeDbgCall("LogRegionalLuxuryCounts-postVanilla", function() LogRegionalLuxuryCounts(start_plot_database, "post-vanilla-placement") end);
	WeeveeDbg("PlaceResources done");
	WeeveeDbgCall("MaybePlaceStartTileResource", function() MaybePlaceStartTileResource(start_plot_database) end);

	WeeveeDbgCall("PlaceOasisForcedHorses", PlaceOasisForcedHorses);
	WeeveeDbgCall("PlaceDesertTundraFrontResources", PlaceDesertTundraFrontResources);
	WeeveeDbgCall("PlaceDesertMainlandResourceBoost", PlaceDesertMainlandResourceBoost);
	WeeveeDbgCall("PlaceOasisFrontColumnExtras", PlaceOasisFrontColumnExtras);
	WeeveeDbgCall("PlaceMurkTundraSheepStone", PlaceMurkTundraSheepStone);
	WeeveeDbgCall("PlaceMurkWheatAndMarshStone", PlaceMurkWheatAndMarshStone);
	WeeveeDbgCall("PlaceMurkSnowStoneIron", PlaceMurkSnowStoneIron);
	WeeveeDbgCall("PlaceFrostySnowStoneIron", PlaceFrostySnowStoneIron);
	WeeveeDbgCall("PlacePeaksPlainsCattle", PlacePeaksPlainsCattle);
	WeeveeDbgCall("PlaceWastelandTundraWheatSheep", PlaceWastelandTundraWheatSheep);
	WeeveeDbgCall("StripBarrierResources", StripBarrierResources);
	WeeveeDbgCall("WastelandMiningLuxFlatTundraToHill", WastelandMiningLuxFlatTundraToHill);
	WeeveeDbgCall("AddForestToResource", function() start_plot_database:AddForestToResource() end);
	WeeveeDbgCall("WastelandTundraStartHillForest", function() WastelandTundraStartHillForest(start_plot_database) end);
	WeeveeDbgCall("AddSnowForests", AddSnowForests);
	WeeveeDbgCall("StripOasisBarrierForests", StripOasisBarrierForests);
	WeeveeDbgCall("StripBrambleSeparatorFeatures", StripBrambleSeparatorFeatures);
	WeeveeDbgCall("PlaceBrambleSaltFish", PlaceBrambleSaltFish);
	WeeveeDbgCall("ForestTundraSeparatorResources", ForestTundraSeparatorResources);
	WeeveeDbgCall("AddBarrierOases", AddBarrierOases);
	WeeveeDbgCall("AddWastelandFallout", AddWastelandFallout);
	WeeveeDbgCall("AddWetlandBarrierFeatures", AddWetlandBarrierFeatures);
	
	if IsOldSnow() or IsSnowBarrier() then
		WeeveeDbgCall("ClearRiversNearBarrier", ClearRiversNearBarrier);
	end
	WeeveeDbgCall("CullShortRivers", CullShortRivers);
	WeeveeDbgCall("CullWestCoastShortRivers", CullWestCoastShortRivers);
	WeeveeDbgCall("PurgeNearStartLakeFish", PurgeNearStartLakeFish);
	WeeveeDbgCall("FixNorthUniqueLuxuries", FixNorthUniqueLuxuries);
	WeeveeDbgCall("StripOasisWestSparseLux", StripOasisWestSparseLux);
	WeeveeDbgCall("EnsureOasisUniqueLuxuries", EnsureOasisUniqueLuxuries);
	WeeveeDbgCall("ThinOasisCoastalLuxuries", ThinOasisCoastalLuxuries);
	WeeveeDbgCall("EnsureMajorIronHills", EnsureMajorIronHills);
	WeeveeDbgCall("StripFrostySnowSparseLux", StripFrostySnowSparseLux);
	WeeveeDbgCall("EnsureLuxuryQuota", EnsureLuxuryQuota);
	WeeveeDbgCall("EnsureStartLuxuryFloor", EnsureStartLuxuryFloor);
	WeeveeDbgCall("StripStartTileLuxuries", StripStartTileLuxuries);
	WeeveeDbgCall("ConvertFlatDesertSaltCopper", ConvertFlatDesertSaltCopper);
	WeeveeDbgCall("StripIllegalMountainResources", StripIllegalMountainResources);
	WeeveeDbgCall("StripInvalidWetFeatures", StripInvalidWetFeatures);
	-- Same reasoning as CapSeaResources below: StripBarrierResources (much
	-- earlier, before AddForestToResource/EnsureLuxuryQuota/
	-- EnsureStartLuxuryFloor) only catches what existed at that point --
	-- any luxury-rescue pass after it can still add a resource onto the
	-- separator strip. This is the true final word on "never a resource on
	-- the strip", run after every pass that could add one.
	WeeveeDbgCall("StripBrambleSeparatorResources", StripBrambleSeparatorResources);
	-- Runs last, not before the luxury-quota/floor passes above: any of them
	-- can place a pearls/whale/crab to help hit a target, and a sea-resource
	-- cap that runs before that can't catch what gets added after it.
	WeeveeDbgCall("CapSeaResources", CapSeaResources);
	-- Everything below that can still move a start or edit a plot is confined
	-- to the west/canonical side only (IsMirrorEastSubject gates every one of
	-- them) and must run BEFORE the mirror copy, never after -- the copy is
	-- the single, sole source of truth for the east side's terrain, resources
	-- and start positions, and must therefore be the very last mutating step.
	-- This guarantees byte-for-byte mirror symmetry: nothing downstream ever
	-- computes anything for the east half independently again.
	WeeveeDbgCall("FrostyFixSnowStarts", FrostyFixSnowStarts);
	WeeveeDbgCall("ClampPlayerStartsOffEdges", ClampPlayerStartsOffEdges);
	WeeveeDbgCall("NudgePlayerStartsMinDist", function() NudgePlayerStartsMinDist(7) end);
	WeeveeDbgCall("StripNonBonusStartTileResources", StripNonBonusStartTileResources);
	WeeveeDbgCall("FrostyThawStartResources", FrostyThawStartResources);
	WeeveeDbgCall("EnsureRegionalLuxuryTarget", function() EnsureRegionalLuxuryTarget(start_plot_database) end);
	WeeveeDbgCall("EnsureLuxuryQuota-postRegionalForce", EnsureLuxuryQuota);
	WeeveeDbgCall("TrimLuxuryQuotaExcess", function() TrimLuxuryQuotaExcess(start_plot_database) end);
	WeeveeDbgCall("EnsureFurOnTundraHasForest", EnsureFurOnTundraHasForest);
	WeeveeDbgCall("OasisJadeFlatDesertToHill", OasisJadeFlatDesertToHill);
	WeeveeDbgCall("LogRegionalLuxuryCounts-preMirror", function() LogRegionalLuxuryCounts(start_plot_database, "pre-mirror-final") end);
	WeeveeDbg("before mirror");
	if DEF_MIRRORED == 1 then
		WeeveeDbgCall("MirrorPlotsAfterResourcePlacement", MirrorPlotsAfterResourcePlacement);
	end
	WeeveeDbgCall("WeeveeDbgBarrierWidths", WeeveeDbgBarrierWidths);
	WeeveeDbgCall("WeeveeDbgWaterCount", WeeveeDbgWaterCount);
	WeeveeDbg("StartPlotSystem done");
end
------------------------------------------------------------------------------
-- Diagnostic for the regional-luxury shortfall investigation. Counts, per
-- west-side region only (pre-mirror -- the east half is just a copy), how
-- many tiles currently carry that region's assigned regional luxury type.
-- Call once right after PlaceResourcesAndCityStates (the vanilla, pre-strip
-- baseline) and again right before the mirror copy (the final pre-mirror
-- state) to see how much each strip/cap pass is actually costing per region.
function LogRegionalLuxuryCounts(asp, stage)
	if asp == nil or asp.region_luxury_assignment == nil or asp.player_ID_list == nil then
		return
	end
	local iW, iH = Map.GetGridSize();
	local maxX = iW - 1;
	if DEF_MIRRORED == 1 then
		maxX = math.floor(iW / 2) - 1;
	end
	local counts = {};
	local y = 0;
	while y < iH do
		local x = 0;
		while x <= maxX do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				local res = plot:GetResourceType(-1);
				if res ~= -1 then
					counts[res] = (counts[res] or 0) + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	WeeveeDbgPersist("--- Regional Luxury Counts [" .. tostring(stage) .. "] (west half, pre-mirror) ---");
	local total = 0;
	local region_number = 1;
	while region_number <= asp.iNumCivs do
		local playerNum = asp.player_ID_list[region_number];
		local player = nil;
		if playerNum ~= nil then
			player = Players[playerNum];
		end
		if player ~= nil and player:IsAlive() then
			local sp = player:GetStartingPlot();
			if sp ~= nil and (DEF_MIRRORED ~= 1 or IsMirrorEastSubject(sp:GetX(), sp:GetY()) == false) then
				local resID = asp.region_luxury_assignment[region_number];
				local n = 0;
				if resID ~= nil then
					n = counts[resID] or 0;
				end
				WeeveeDbgPersist("Region#" .. region_number .. " LuxID=" .. tostring(resID) .. " count=" .. n);
				total = total + n;
			end
		end
		region_number = region_number + 1;
	end
	WeeveeDbgPersist("--- Regional Luxury Total [" .. tostring(stage) .. "]: " .. total .. " ---");
end
------------------------------------------------------------------------------
-- TEMPORARY diagnostic for the water-budget investigation. Counts final salt
-- water (ocean/coast, explicitly excluding lakes) vs lake tiles, tagged with
-- the active climate, so results from different climate rolls can be told
-- apart in weevee_dbg.log. Safe to delete once the water question is settled.
function WeeveeDbgWaterCount()
	local iW, iH = Map.GetGridSize();
	local cfg = GetBarrierConfig();
	local kind = "nil";
	if cfg ~= nil then
		kind = tostring(cfg.kind);
	end
	local saltWater = 0;
	local lakeWater = 0;
	local land = 0;
	local y = 0;
	while y < iH do
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil then
				if plot:IsWater() then
					if plot:IsLake() then
						lakeWater = lakeWater + 1;
					else
						saltWater = saltWater + 1;
					end
				else
					land = land + 1;
				end
			end
			x = x + 1;
		end
		y = y + 1;
	end
	local total = iW * iH;
	local line = "WATER COUNT kind=" .. kind .. " iW=" .. iW .. " iH=" .. iH .. " total=" .. total
		.. " saltWater=" .. saltWater .. " lakeWater=" .. lakeWater .. " land=" .. land
		.. " saltWaterPct=" .. string.format("%.1f", 100 * saltWater / total);
	WeeveeDbg(line);
	WeeveeDbgPersist(line);
end
------------------------------------------------------------------------------
-- TEMPORARY diagnostic for the Standard-Diagonal barrier-width investigation.
-- Logs the actual final snow-terrain run at each row to weevee_dbg.log. Safe
-- to delete once the width question is settled.
function WeeveeDbgBarrierWidths()
	if IsTiltedMirrorAxis() == false then
		return
	end
	local iW, iH = Map.GetGridSize();
	local wrapN, centerN = ResolveSnowWrapWidths();
	WeeveeDbg("BARRIER DIAG iW=" .. iW .. " iH=" .. iH .. " centerN=" .. centerN .. " wrapN=" .. wrapN);
	local y = 0;
	while y < iH do
		local cols = {};
		local x = 0;
		while x < iW do
			local plot = Map.GetPlot(x, y);
			if plot ~= nil and plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then
				table.insert(cols, x);
			end
			x = x + 1;
		end
		local line = "row " .. y .. " snow_cols=[";
		local i = 1;
		while i <= #cols do
			line = line .. cols[i];
			if i < #cols then
				line = line .. ",";
			end
			i = i + 1;
		end
		line = line .. "] fold_mid=" .. TiltedFoldMid(y);
		WeeveeDbg(line);
		local win = GetSnowWrapColumns(iW, y);
		local mirrored = (DEF_MIRRORED == 1);
		local wi = 1;
		local winLine = "  window: ";
		while wi <= #win do
			local wx = win[wi];
			local owned = MirrorOwnsPlot(wx, y, mirrored, iW);
			local terrName = "nil";
			local plot = Map.GetPlot(wx, y);
			if plot ~= nil then
				local t = plot:GetTerrainType();
				if t == TerrainTypes.TERRAIN_SNOW then terrName = "SNOW";
				elseif t == TerrainTypes.TERRAIN_TUNDRA then terrName = "TUNDRA";
				elseif t == TerrainTypes.TERRAIN_OCEAN then terrName = "OCEAN";
				elseif t == TerrainTypes.TERRAIN_COAST then terrName = "COAST";
				elseif t == TerrainTypes.TERRAIN_GRASS then terrName = "GRASS";
				elseif t == TerrainTypes.TERRAIN_PLAINS then terrName = "PLAINS";
				elseif t == TerrainTypes.TERRAIN_DESERT then terrName = "DESERT";
				else terrName = "OTHER(" .. tostring(t) .. ")"; end
			end
			winLine = winLine .. "x=" .. wx .. ":owned=" .. tostring(owned) .. ":" .. terrName .. "  ";
			wi = wi + 1;
		end
		WeeveeDbg(winLine);
		y = y + 1;
	end
end
------------------------------------------------------------------------------
local CoreGenerateMap = GenerateMap;
function GenerateMap()
	local maxAttempts = 8;
	local attempt = 1;
	while attempt <= maxAttempts do
		print("########## Weevee GenerateMap attempt", attempt, "/", maxAttempts);
		if attempt > 1 then
			ResetWeeveeMapAttempt();
		end
		weeveeStartDistFail = false;
		CoreGenerateMap();
		local ok, nUnique, nDup, nTrip = LuxuryQuotaMet();
		local wantU, wantD, wantT = ResolveLuxTargets();
		if weeveeStartDistFail then
			print("Start min-dist 7 rejected");
		end
		if ok and weeveeStartDistFail ~= true then
			print("Luxury quota accepted unique", nUnique, "/", wantU, "dup", nDup, "/", wantD, "trip", nTrip, "/", wantT);
			return
		end
		print("Luxury quota rejected unique", nUnique, "/", wantU, "dup", nDup, "/", wantD, "trip", nTrip, "/", wantT);
		if attempt >= maxAttempts then
			print("Map retry exhausted, keeping last map");
			return
		end
		attempt = attempt + 1;
	end
end
------------------------------------------------------------------------------

