import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FeeVaultModule", (m) => {
  // Taxa em basis points: 100 = 1% (máximo 500 = 5%)
  const feeBps = m.getParameter("feeBps", 100n);
  const vault = m.contract("FeeVault", [feeBps]);
  return { vault };
});
