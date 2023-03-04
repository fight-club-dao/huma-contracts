const {deploy} = require("../utils.js");

const HUMA_OWNER_ADDRESS='0x81a943AE0218D70e7a82896ceC7E9c5ccD48663F';
const POOL_OWNER_ADDRESS='0x14dC79964da2C08b23698B3D3cc7Ca32193d9955';

async function deployContracts() {
    const network = (await hre.ethers.provider.getNetwork()).name;
    console.log("network : ", network);
    const accounts = await hre.ethers.getSigners();
    if (accounts.length == 0) {
        throw new Error("Accounts not set!");
    }
    const deployer = await accounts[0];
    console.log("deployer address: " + deployer.address);

    const eaService = await accounts[4];
    console.log("ea service address: " + eaService.address);

    const usdc = await deploy("TestToken", "USDC");
    const evaluationAgentNFT = await deploy("EvaluationAgentNFT", "EANFT", [], eaService);
    const invoiceNFT = await deploy("InvoiceNFT", "RNNFT", [usdc.address]);

    const humaConfig = await deploy("HumaConfig", "HumaConfig");
 
    const bc_feeManager = await deploy("BaseFeeManager", "BaseCreditPoolFeeManager");
    const bc_hdtImpl = await deploy("HDT", "BaseCreditHDTImpl");
    const bc_hdt = await deploy("TransparentUpgradeableProxy", "BaseCreditHDT", [
        bc_hdtImpl.address,
        POOL_OWNER_ADDRESS,
        [],
    ]);
    const bc_poolConfig = await deploy("BasePoolConfig", "BaseCreditPoolConfig");

    const bc_poolImpl = await deploy("BaseCreditPool", "BaseCreditPoolImpl");
    const bc_pool = await deploy("TransparentUpgradeableProxy", "BaseCreditPool", [
        bc_poolImpl.address,
        HUMA_OWNER_ADDRESS,
        [],
    ]);
    // End of deploying base credit pool

}

deployContracts()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
