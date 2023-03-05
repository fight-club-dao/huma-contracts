const {deploy, getDeployedContracts} = require("../utils.js");
const {BigNumber: BN} = require("ethers");

async function main() {
    const network = (await hre.ethers.provider.getNetwork()).name;
    console.log("network : ", network);
    const accounts = await hre.ethers.getSigners();
    const [deployer, treasury, eaService, pdsService, ea, proxyOwner] =
        await hre.ethers.getSigners();
    console.log("Deployer address: ", deployer.address);
    console.log("Treasury address: ", treasury.address);
    console.log("EaService address:", eaService.address);
    console.log("EA address", ea.address);

    const decimals = 6;

    deployedContracts = await getDeployedContracts();
    const BaseCreditPool = await hre.ethers.getContractFactory("BaseCreditPool");
    pool = BaseCreditPool.attach(deployedContracts["BaseCreditPool"]);

    // const USDC = await hre.ethers.getContractFactory("USDC");
    // usdc = USDC.attach(deployedContracts["USDC"]);
    const usdc = await deploy("TestToken", "USDC", [], deployer, {gasLimit: 3_000_000});

    const amountOwner = BN.from(150_000).mul(BN.from(10).pow(BN.from(decimals)));
    const amountEA = BN.from(10_000).mul(BN.from(10).pow(BN.from(decimals)));
    
    // console.log("send funds treasury");
    // await usdc.connect(treasury).approve(pool.address, amountOwner);
    // await pool.connect(treasury).makeInitialDeposit(amountOwner);
    // console.log("send funds ea");
    // await usdc.connect(ea).approve(pool.address, amountEA);
    // await pool.connect(ea).makeInitialDeposit(amountEA);

    console.log("Enabling pool");
    await pool.addApprovedLender(ea.address);
    await pool.addApprovedLender(treasury.address);

    // await pool.enablePool();
    // console.log("Pool is enabled");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
