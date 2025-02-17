// WORKAROUND: When including files in main, constants don't get transferred, so all constants are specified as regular entries instead
// They do work when including in other files, but not the main script
// TODO: Figure out why, and how to fix it if possible

// enum LogLevels { always, info, warning, error, debug, trace }
// enum PtexSpawnflags { startActive=1, alwaysUpdate=2 }
LogLevels <- { always=0, info=1, warning=2, error=3, debug=4, trace=5 }
PtexSpawnflags <- { none=0, startActive=1, alwaysUpdate=2 }

// Matches env_projectedtexture keyvalues to their cooresponding outputs
ptexOutputKV <- {
    // These two are based on the parent, rather than being absolute
    // origin          = "SetLocalOrigin",
    // angles          = "SetLocalAngles",
    parentname      = "SetParent",
    texturename     = "SpotlightTexture", // Supposedly this is disabled in Portal 2, so you should set the keyvalue manually as well
    lightfov        = "FOV",
    enableshadows   = "EnableShadows",
    target          = "Target",
    cameraspace     = "CameraSpace",
    lightonlytarget = "LightOnlyTarget",
    lightworld      = "LightWorld",
    lightcolor      = "LightColor",
    style           = "SetLightStyle",
    pattern         = "SetPattern",
    nearz           = "SetNearZ",
    farz            = "SetFarZ"
}

// Stores all keyvalues that we hijack for simulating turning the projtex off
// The value determines what they should be changed to in the off state
hijackedKV <- {
    lightfov      = 0.0, // Negative numbers are equivalent to their positive counterparts
    farz          = 0, // FarZ flickers at 0, negative numbers don't seem to do anything
    enableshadows = 0
    // TODO: Set AlwaysUpdateOff when the ptex is off, to prevent unnecessary potential calculations
}

/*
 * Stores the default values all projected textures will be initialized with
 * Most of these are important to set here, otherwise the script wouldn't work
 * 
 * Edit the values here if you want different defaults
 * - Do NOT change anything above the "Hijacked" section
 * - Do NOT remove anything above the "Optional" section (they are expected to always exist)
 */
defaultKV <- {
    // These four are grabbed directly from the original ptex through vscript
    // TODO: Maybe let these be changeable from here
    targetname = "",
    parentname = "",
    
    origin = "",
    angles = "",
    
    // Special
    vscripts = "MultiProj/ptex.nut", // Core script that handles multi-projtex functionality
    
    // Hijacked
    colortransitiontime = 0.5, // Needs to be reset later since we change it on startup
    // Keys used to simulate TurnOff
    lightfov            = 90.0,
    farz                = 750.0,
    enableshadows       = 1, // Most likely you want this on if you're even using this script
    
    // Optional defaults
    spawnflags = 0, // "Start Actve" and "Always Update" false
};

function round(value, decimals) {
    local factor = pow(10, decimals);
    return floor(value * factor + 0.5) / factor;
}

/*
 * Utility function for quick logging
 *
 * Parameters:
 *  message: The message to print
 *  severity: The severity of the message. This automatically assumes a developer level
 *  newline: If the message should print a newline at the end
 *  alwaysShowTime: Whether to always show the timestamp or if it should be based on severity
 *  developerLevel: Override for the auto detection based on the severity
 */
function logPrint(message, severity = LogLevels.info, newLine = true, alwaysShowTime = false, developerLevel = -1) {
    if (!_multiproj__loggingEnabled) return;
    
    local severityIndicator = ""
    
    local fileName = getstackinfos(2).src;
    
    local time = "("+round(Time(), 2)+") ";
    local stack = fileName.slice(0, fileName.len()-4) // File name minus .nut
                + "("+getstackinfos(2).line+")" + "::"
                + getstackinfos(2).func + " ";
    
    // Disable stack for certain levels
    if (severity == LogLevels.always || severity == LogLevels.info) {
        if (!alwaysShowTime) time = "";
        stack = "";
    }
    
    switch (severity) {
        case LogLevels.always:  if (developerLevel == -1) developerLevel = 0; severityIndicator = "";           break;
        case LogLevels.error:   if (developerLevel == -1) developerLevel = 0; severityIndicator = "(ERROR) ";   break;
        case LogLevels.info:    if (developerLevel == -1) developerLevel = 1; severityIndicator = "(INFO) ";    break;
        case LogLevels.warning: if (developerLevel == -1) developerLevel = 2; severityIndicator = "(WARNING) "; break;
        case LogLevels.debug:   if (developerLevel == -1) developerLevel = 3; severityIndicator = "(DEBUG) ";   break;
        case LogLevels.trace:   if (developerLevel == -1) developerLevel = 4; severityIndicator = "(TRACE) ";   break;
        default: developerLevel = 0;
    }
    
    if (GetDeveloperLevel() >= developerLevel) {
        local messageFormatted = time + "[MultiProj] " + stack + severityIndicator + "> " + message;
        if (newLine) messageFormatted += "\n";
        print(messageFormatted);
    }
}

// HACK: Hacky functions to simulate pausing code
// Firing an output already takes time on it's own, so the time parameter isn't exact and will always delay a little bit even if set to zero
function pauseExecution(generator, time = 0.0) {
    logPrint("Pausing generator " + generator.tostring(), LogLevels.debug);
    EntFireByHandle(self, "RunScriptCode", "resumeExecution("+generator+");", time, self, self);
}
// Resume function
function resumeExecution(generator) {
    logPrint("Resuming generator " + generator, LogLevels.debug);
    resume generator;
}

/*
 * Sets a keyvalue in an entity (primarily designed for env_projectedtexture)
 * NOTE: When running inputs for keyvalues, there is a delay due to the I/O system. This may cause timing issues if not dealt with properly
 * TODO: Separate out env_projectedtexture-specific stuff to generalize this function
 *
 * Returns:
 *  True if a cooresponding output was found, false otherwise
 * 
 * Parameters:
 *  handle: The entity handle
 *  key: The key to set
 *  value: The value to set it to
 *  setByInput: Determines whether the keyvalue should be checked for a cooresponding input to fire (so the keyvalue properly updates)
 *  setByKV: Determines whether the keyvalue should be set directly. This is always true if the keyvalue has no cooresponding input
 */
function ptexSetKeyvalue(handle, key, value, setByInput = true, setByKV = false) {
    logPrint("handle = " + handle + " , Key = " + key + " , value = " + value, LogLevels.trace);
    
    if (!setByInput && !setByKV) {
        logPrint("setByInput and setByKV both false! No keyvalues will be set", LogLevels.warning);
        return;
    }
    
    // Special cases
    switch (key.tolower()) {
        // Vscripts require special initialization
        case "vscripts": {
            // TODO: This only allows one set of scripts to ever be added, in our case the ptex script
            if (!handle.GetScriptScope()) {
                handle.ValidateScriptScope();
                DoIncludeScript(value, handle.GetScriptScope());
            }
            break;
        }
        // Spawnflags don't do anything because we can only set values post-spawn, so we deal with them manually
        case "spawnflags": {
            // Don't attempt to run TurnOn here, as we use this function prior to hooking into the ptex
            // if (value & PtexSpawnflags.startActive) EntFireByHandle(handle, "TurnOn", "", 0, self, self);
            if (ensureInt(value) & PtexSpawnflags.alwaysUpdate) EntFireByHandle(handle, "AlwaysUpdateOn", "", 0, self, self);
            break;
        }
        
        // We can set these through code so may as well
        case "origin": handle.SetAbsOrigin(value); break;
        case "angles": handle.SetAngles(value.x, value.y, value.z); break;
        
        // Setting this through the output is disabled in Portal 2, for whatever reason
        // That means this is unchangeable from the default technically, but may as well at least try to set the keyvalue
        case "texturename": setByKV = true; break;
        
        default: {};
    }
    
    if (setByInput && key in ptexOutputKV) {
        EntFireByHandle(handle, ptexOutputKV[key], value.tostring(), 0, self, self);
        return true;
    } else setByKV = true;
    if (setByKV) setKeyValueRaw(handle, key, value);
    
    return false;
}

/*
 * Sets a keyvalue using the cooresponding type function
 * Returns:
 *  True on success
 * 
 * Parameters:
 *  handle: The entity handle
 *  key: The key to set
 *  value: The value to set it to
 */
function setKeyValueRaw(handle, key, value) {
    switch (typeof value) {
        case "integer": handle.__KeyValueFromInt(key, value);    return true;
        case "float":   handle.__KeyValueFromFloat(key, value);  return true;
        case "string":  handle.__KeyValueFromString(key, value); return true;
        case "Vector":  handle.__KeyValueFromVector(key, value); return true; // TODO: Test this
        
        default: {
            logPrint("ERROR: Invalid key type passed to setKeyValueRaw()!\n"
                   + "    >> Expected <integer,float,string,vector>, got <"+typeof value+">\n"
                   , LogLevels.error);
        }
    }
    
    return false;
}

/*
 * Generates a new unique targetname
 * If the given parameters don't generate a unique name, incremental digits will be added until it's unique
 * 
 * Parameters:
 *  baseName: The base name to start from
 *  prefix: The prefix to add to the basename
 *  postfix: The postfix to add to the basename
 */
function createUniqueTargetname(baseName = "", prefix = "__multiproj_", postfix = "_" + RandomInt(1000, 9999) + RandomInt(1000, 9999)) {
    local name = prefix + baseName + postfix;
    
    // Append a number to the end if it's not unique
    if (Entities.FindByName(null, name)) {
        local ent = null;
        name += "_" + 0;
        for (local i = 1; ent = Entities.FindByName(ent, name); i++)
            name = name.slice(0, name.len()-1) + i;
    }
    
    logPrint("Created unique name: " + name, LogLevels.trace);
    return name;
}

// Returns the values of an array as a string
function arrayToString(array, separator=" ") {
    if (typeof array != "array") {
        logPrint("ERROR: Not an array!", LogLevels.error);
        return null;
    }
    local string = "";
    foreach (value in array) string += value.tostring() + separator;
    
    return string.slice(0, string.len()-1);
}

// Returns the value as an integer
function ensureInt(value) {
    switch (typeof value) {
        // TODO: Deal with more types
        case "string": value = value.tointeger(); break;
        default: {};
    }
    return value;
}