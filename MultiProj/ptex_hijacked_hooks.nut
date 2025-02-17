// The user can still change the hijacked keyvalues at any time, even when the ptex is supposed to be off,
// so we hook into the inputs to stop this. This must be in a separate file since the initialization code
// runs these outputs, so we can't hook them until they are ready

logPrint("Loaded hijacked hooks script functions", LogLevels.debug);

function InputFOV()     { return Input_HijackedKV("FOV"); }
function InputSetFarZ() { return Input_HijackedKV("SetFarZ"); }

function Input_HijackedKV(input) {
    // Block output only if we are inactive and "not ready" (meaning TurnOn or TurnOff weren't used)
    if (!isActive && !isReadyForToggle) {
        // We can't retrieve the value associated with the input, so produce a warning instead
        logPrint(
            "Attempted to set value of hijacked keyvalue via input "+input+" while env_projectedtexture "+self.GetName()+" was disabled!\n"
           +"    Call notifyKVUpdate() if you want to update this value", LogLevels.warning);
        return false;
    }
    return true;
}