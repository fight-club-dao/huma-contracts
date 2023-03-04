const {getDeployedContracts} = require("../utils.js");
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

    const USDC = await hre.ethers.getContractFactory("TestToken");
    usdc = USDC.attach(deployedContracts["USDC"]);

    // const HDT = await hre.ethers.getContractFactory("HDT");
    // hdt = HDT.attach(deployedContracts["BaseCreditHDT"]);
    // console.log(await hdt.withdrawableFundsOf(treasury.address));
    // console.log(await hdt.withdrawableFundsOf(deployer.address));
    
    let usdcFromEa = usdc.connect(ea);
    console.log(usdcFromEa.signer.address);
    
    let poolEa = pool.connect(ea);
    let tx;
    const amountOwner = BN.from(20_000).mul(BN.from(10).pow(BN.from(decimals)));
    // tx = await usdcFromEa.mint(ea.address, amountOwner.mul(2), {gasLimit: 1000000});
    // console.log(tx.hash);
    // await tx.wait();
    // tx = await usdcFromEa.approve(pool.address, amountOwner.mul(2));
    // console.log(tx.hash)
    // await tx.wait();

    // tx = await poolEa.makeInitialDeposit(amountOwner, {gasLimit: 3000000});
    // console.log(tx.hash);
    // await tx.wait();
    // console.log("Initial deposit done");
    const MAX_FEE_PER_GAS = 30_000_000_000;
    const MAX_PRIORITY_FEE_PER_GAS = 2_000_000_000;
    try {
        tx = await pool.enablePool({gasPrice: 20592675960});
    } catch (e) {
        console.log(e.message);
        throw e;
    }
    console.log(tx.hash);
    await tx.wait();
    console.log("Pool is enabled");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
