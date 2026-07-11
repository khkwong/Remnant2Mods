print("[ZZTestMod] Loaded and running.\n")

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
  print("[ZZTestMod] ClientRestart fired - hook is working.\n")
end)