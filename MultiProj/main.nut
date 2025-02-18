/*
 * Author: BetweenReality
 * Purpose: A script to allow for multiple active env_projectedtextures at a time for engines
 *          that don't support it (like Portal 2). It utilizes an oversight
 *          in the code that doesn't check for active projected textures when creating
 *          a new one with commands. Since they start active by default, it never reaches
 *          the check to turn the others off.
 *          
 *          This script initializes all env_projectedtextures by creating new ones at the locations
 *          of the old ones, and binds another script to them that controls them at runtime
 */

// TODO: Make a better method for scheduling events. Too many times does logic fail because stuff that I expected to happen hasn't happened yet
// which leads to a lot of hacky "waiting" code (either through yield or EntFire). I fixed a lot of it but there is still some strangeness
// TODO: Sometimes these scripts just randomly don't load for some reason. It might be because I usually try to reload the map right
// after I save the file to test my changes, which causes the file to be locked for a few seconds or something, but I don't know if that's the only reason

// BUG: Spamming TurnOn and TurnOff might cause the ptex to not turn back on, even though the inputs are sent. Might be an engine bug
// BUG: Running SetPattern changes the pattern for ALL projectedtextures that have AlwaysUpdate enabled (which is required).
// Sounds like another engine bug (or intentional, since only 1 ptex is expected to be active)

IncludeScript("MultiProj/utils.nut");

::_MULTIPROJ__VERSION <- "1.0.0";
::_multiproj__isInitialized <- false;
::_multiproj__loggingEnabled <- true;

// Stores all ptex handles
projectedTextures <- [];
projectedTexturesOrg <- [];

function init() {
    logPrint("Initializing Multi-Projtex Script, version " + _MULTIPROJ__VERSION, LogLevels.always);
    
    // Get all projected textures. This is separate from the next loop since otherwise it would find our newly created ones
    // NOTE: This does not account for any additional env_projectedtextures created at runtime not by us (like from point_template or otherwise)
    local currentEntity = null;
    while (currentEntity = Entities.FindByClassname(currentEntity, "env_projectedtexture")) {
        projectedTexturesOrg.push(currentEntity);
        logPrint("Caching ptex " + currentEntity, LogLevels.trace);
    }
    
    projectedTextures.resize(projectedTexturesOrg.len());
    
    // Replace all projected textures with our new ones
    for (local i = 0; i < projectedTexturesOrg.len(); i++) {
        local ptexOriginal = projectedTexturesOrg[i];
        logPrint("Replacing ptex " + ptexOriginal, LogLevels.debug);
        
        local keyvalues = clone defaultKV;
        
        // Set the new name to the same as the old one so anything targeting it still works properly
        keyvalues.targetname = ptexOriginal.GetName();
        keyvalues.origin     = ptexOriginal.GetOrigin();
        keyvalues.angles     = ptexOriginal.GetAngles();
        
        // Get parentname from original projtex
        if (ptexOriginal.GetMoveParent() != null) {
            keyvalues.parentname = ptexOriginal.GetMoveParent().GetName();
            // Set "Always Update" flag as a default. Turning the ptex on and off won't update it since we fake it, so this is more necessary
            keyvalues.spawnflags = keyvalues.spawnflags | PtexSpawnflags.alwaysUpdate;
        }
        
        if (!keyvalues.targetname) {
            logPrint("env_projectedtexture " + ptexOriginal + " without a name! Generating a new name", LogLevels.error);
            keyvalues.targetname = createUniqueTargetname();
        }
        
        // Create a unique name so the old ptex doesn't interfere with the new one
        ptexOriginal.__KeyValueFromString("targetname", createUniqueTargetname(ptexOriginal.GetName()));
        
        projectedTextures[i] = createProjectedTexture(keyvalues);
        
        // HACK: Creating the next Ptex too early causes EnforceSingleProjectionRules to be run, so we have to wait
        // I assume that might be because the previous Ptex didn't get renamed on time or something
        // so it gets associated with the new one which we might send the TurnOn input to (if Start Active is on)
        yield pauseExecution("main_initgen");
    }
    
    // Separate loop, for timing reasons
    for (local i = 0; i < projectedTextures.len(); i++) {
        // If the original ptex had a child, change the parent to the new one
        if (projectedTexturesOrg[i].FirstMoveChild())
            EntFireByHandle(projectedTexturesOrg[i].FirstMoveChild(), "SetParent", projectedTextures[i].GetName(), 0, self, self);
        
        // Load the script into all the new projected textures
        projectedTextures[i].GetScriptScope().init(projectedTexturesOrg[i]);
    }
    
    // Ensure multiple initialization doesn't occur
    _multiproj__isInitialized = true;
    
    logPrint("Multi-Projtex Script Initialized", LogLevels.always);
}

/* 
 * Creates a projected texture
 * 
 * Parameters:
 *  keyvalues: The keyvalues to set on this entity
 */
function createProjectedTexture(keyvalues = {}) {
    logPrint("Running createProjectedTexture()", LogLevels.trace);
    
    // A benefit of doing this directly (as opposed to create_flashlight) is that we don't have to wait on the I/O queue
    local handle = Entities.CreateByClassname("env_projectedtexture");
    keyvalues = clone keyvalues;
    
    // Set Default keyvalues. We don't have access to the user's selected keyvalues until later so we can't set those yet
    // This also has to happen here and not in the ptex script since it needs information like targetname to exist before it
    // can initialize, and we only have access to those values here (And I don't want to make more global variables)
    foreach (key, value in keyvalues) {
        ptexSetKeyvalue(handle, key, value);
    }
    
    // Disable the projtex if StartActive isn't set. Must be done outside the other loop to prevent it from overwriting the value
    if ("spawnflags" in keyvalues && !(keyvalues.spawnflags & PtexSpawnflags.startActive)) {
        foreach (key, value in hijackedKV) {
            ptexSetKeyvalue(handle, key, hijackedKV[key].tostring());
        }
    }
    
    return handle;
}

// Disables all log output
// Run this if you don't want any log output
function disableLogging() { _multiproj__loggingEnabled = false }

// Run init automatically
main_initgen <- init();
resume main_initgen;