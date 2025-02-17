/*
 * Author: BetweenReality
 * Purpose: Handles dealing with keyvalues for env_projectedtextures at runtime
 *          Must be attached to an env_projectedtexture to work properly
 *          Certain keyvalues are also controlled to simulate turning off
 */

IncludeScript("MultiProj/utils.nut");

isActive <- true; // If the projtex is currently active. Starts true since technically it does start active
isReadyForToggle <- false; // If TurnOn or TurnOff inputs are ran, this is set to true. Otherwise we aren't ready to change states
keyvaluesInitialized <- false; // A bit misleading since this depends on setKeyvalues() being called on startup, which may not always happen

// Stores all known keyvalues that have been changed from default
// NOTE: Any keyvalues changed through inputs without using the notifyKVUpdate() function will NOT be the same here
// That doesn't really matter though since we only really read from this during initialization, or for hijacked keys
currentKeyvalues <- clone defaultKV;

getUserKV_generator <- null;

// Initialize this env_projectedtexture
function init(ptexOriginal) {
    logPrint("Created Projtex: " + self, LogLevels.debug);
    
    // The defaults from the other script should have already turned us on if needed, so we only need to notify our variable here
    if (!(currentKeyvalues.spawnflags & PtexSpawnflags.startActive)) isActive = false;
    
    // getUserKV(ptexOriginal);
    getUserKV_generator = getUserKV(ptexOriginal);
    resume getUserKV_generator;
}

/*
 * Retrieve user-selected keyvalues, if any were set. This should only be run once at initialization
 * 
 * Parameters:
 *  ptexOriginal: The handle of the original env_projectedtexture, which contains the info we need
 */
function getUserKV(ptexOriginal) {
    logPrint("Running getUserKV() for " + self.GetName(), LogLevels.debug);
    
    // Method 1: Reads the model keyvalue. Expects this format: key1=value1,key2=value with spaces
    // TODO: Is there a keyvalue character limit? If so, this will fail if too many keyvalues are set or they are too long
    local modelNameKV = ptexOriginal.GetModelName();
    
    // WORKAROUND: modelNameKV isn't reading as null for some reason, so use the length
    // I think this might be because all entities have a model kv inherited from CBaseEntity, even if they don't use it
    // Though it also fails if checking for an empty string so ???
    if (modelNameKV.len() != 0) {
        logPrint("Found \"model\" keyvalue in projtex: " + self.GetName(), LogLevels.debug);
        local keyvalues = {};
        local keyvaluesPre = split(modelNameKV, ",");
        
        // Parse the string. Makes no attempt to validate the format
        logPrint("Parsed keyvalues: ", LogLevels.trace);
        for (local i = 0; i < keyvaluesPre.len(); i++) {
            keyvaluesPre[i] = split(keyvaluesPre[i], "=");
            keyvalues[strip(keyvaluesPre[i][0])] <- strip(keyvaluesPre[i][1]);
            logPrint("| " + keyvaluesPre[i][0] + " = " + keyvaluesPre[i][1] + " |", LogLevels.trace);
        }
        
        setKeyvalues(keyvalues);
    }
    // Method 2: Runs OnUser1 which runs setKeyvalues() through hammer, except replacing strings with arrays or sequences of chars
    else {
        // TODO: Way to detect if this succeeds, since if neither this method nor the above method occur we don't ever call setKeyvalues, which is an incomplete initialization
        logPrint("No \"model\" keyvalue detected in ptex " + self.GetName() + ", attempting OnUser1 method", LogLevels.debug)
        EntFireByHandle(ptexOriginal, "FireUser1", "", 0, self, self);
    }
    
    // HACK: Delay killing so that any children can get re-parented to the new ptex on time,
    // and so that it doesn't die before FireUser1 gets called on it
    // ptexOriginal.Destroy();
    EntFireByHandle(ptexOriginal, "Kill", "", 0, self, self);
    
    // HACK: The hijacked hooks interfere with initialization, so only add them after we are done
    // We can't guarantee that setKeyvalues will ever be run (within a timely fashion, at least) so we can't call this in there
    yield pauseExecution("getUserKV_generator");
    DoIncludeScript("MultiProj/ptex_hijacked_hooks.nut", self.GetScriptScope());
}

/*
 * Sets an array of keyvalues
 * Meant to be used through the OnUser1 output of your env_projectedtexture to initialize keyvalues
 * 
 * Parameters:
 *  keyvalues: An array of keyvalues to update. Strings can be passed in as arrays or sequences of chars
 */
function setKeyvalues(keyvalues) {
    logPrint("Running setKeyvalues() for " + self.GetName(), LogLevels.debug);
    
    foreach (key, value in keyvalues) {
        // WORKAROUND: Convert arrays to strings, since strings corrupt the VMF
        // Only works for numeric strings though, like lightcolor. Other strings must be sent as char sequences
        if (typeof value == "array") value = arrayToString(value);
        
        currentKeyvalues[key] <- value;
        
        // If the projtex is off then send the off value instead
        if (!isActive && key in hijackedKV) value = hijackedKV[key];
        ptexSetKeyvalue(self, key, value);
    }
    
    if (!keyvaluesInitialized) {
        logPrint("First time initialization of user keyvalues in " + self.GetName(), LogLevels.debug);
        
        if (ensureInt(currentKeyvalues.spawnflags) & PtexSpawnflags.startActive)
            InputTurnOn();
        
        // Briefly change colortransitiontime since the default value causes a slow fadein when the projtex spawns
        // The code for this uses the value as a speed, rather than a "time until complete"
        // NOTE: This only matters if the projtex is active on spawn AND in immediate view, otherwise it would be fine by the time the player sees it
        ptexSetKeyvalue(self, "colortransitiontime", 100000);
        
        // HACK: For whatever reason this is very picky with the timing, even though the above should always theoretically happen faster
        // Looks like it might be related to the time between the map being loaded and the player gaining control
        // 1.5 seconds seems to be enough 99% of the time
        EntFireByHandle(self, "AddOutput", "colortransitiontime " + currentKeyvalues.colortransitiontime, 1.5, self, self);
        
        keyvaluesInitialized = true;
    }
}

function activate()   { toggle(currentKeyvalues); }
function deactivate() { toggle(hijackedKV); }

// Toggles the state of the projtex. keyvalues should contain the values to change to, based on the keys in hijackedKV
function toggle(keyvalues) {
    logPrint("Running toggle(), current state is " + isActive, LogLevels.trace);
    foreach (key, value in hijackedKV) {
        EntFireByHandle(self, ptexOutputKV[key], keyvalues[key].tostring(), 0.0, activator, caller);
    }
    // Only change active status once all the keyvalues are set, so that the hijacked inputs don't get disabled too early
    EntFireByHandle(self, "RunScriptCode", "setActive();", 0.0, self, self);
}

// Function to set internal active state. Useful when needing to delay this
function setActive(state = !isActive) {
    state = !isActive; // FIXME: The default parameter gets set to the wrong thing but setting it again works???
    
    logPrint("Running setActive() with state " + state, LogLevels.trace);
    isActive = state;
    isReadyForToggle = false;
}

/*
 * Notifies the script that the user wants to update a keyvalue
 * This only needs to be called for keyvalues that we hijacked, and only if the projtex will be turned off and on after changing the keyvalue
 * Additionally you should call this if you ever run setKeyvalues() again post-initialization
 * 
 * Parameters:
 *  key: The key to update
 *  value: The value to update it with
 *  autoSetKV: If we should also update the keyvalue automatically. Useful to save on inputs
 */
function notifyKVUpdate(key, value, autoSetKV=true) {
    currentKeyvalues[key] = value;
    
    if (!(key in hijackedKV)) logPrint("notifyKVUpdate() called for non-hijacked key \"" + key + "\" with value \"" + value + "\"", LogLevels.info);
    else if (!isActive) value = hijackedKV[key]; // Don't inadvertently turn on the ptex
    
    if (autoSetKV) ptexSetKeyvalue(self, key, value);
}

/////////////////
// INPUT HOOKS //
/////////////////

// Reroute TurnOn and TurnOff to our custom functions

function InputTurnOn() {
    if (!isActive) {
        isReadyForToggle = true;
        logPrint("Turning on env_projectedtexture " + self.GetName(), LogLevels.debug);
        activate();
    } else logPrint("Attempted to activate an already active multiproj ("+self.GetName()+") Skipping...", LogLevels.warning);
    return false; // The default code should never be run, or else it would run EnforceSingleProjectionRules and ruin everything
}

function InputTurnOff() {
    if (isActive) {
        isReadyForToggle = true;
        logPrint("Turning off env_projectedtexture: " + self.GetName(), LogLevels.debug);
        deactivate();
    } else logPrint("Attempted to deactivate an already inactive multiproj ("+self.GetName()+") Skipping...", LogLevels.warning);
    return false; // We can't ever shut it off either
}

// Don't run automatically, for timing reasons
// init();
// ptex_initgen <- init();
// resume ptex_initgen;