async function deployContracts(poolOwner, treasury, lender, fees = [10, 100, 20, 500]) {
    // Deploy HumaConfig
    const HumaConfig = await ethers.getContractFactory("HumaConfig");
    humaConfigContract = await HumaConfig.deploy(treasury.address);
    humaConfigContract.setHumaTreasury(treasury.address);
    await humaConfigContract.addPauser(poolOwner.address);
    await humaConfigContract.transferOwnership(poolOwner.address);

    // Deploy Fee Manager
    const feeManagerFactory = await ethers.getContractFactory("BaseFeeManager");
    feeManagerContract = await feeManagerFactory.deploy();
    await feeManagerContract.transferOwnership(poolOwner.address);
    await feeManagerContract.connect(poolOwner).setFees(fees[0], fees[1], fees[2], fees[3]);

    // Deploy TestToken, give initial tokens to lender
    const TestToken = await ethers.getContractFactory("TestToken");
    testTokenContract = await TestToken.deploy();
    await testTokenContract.give1000To(lender.address);
    await testTokenContract.give1000To(poolOwner.address);

    return [humaConfigContract, feeManagerContract, testTokenContract];
}

async function deployAndSetupPool(
    poolOwner,
    proxyOwner,
    evaluationAgent,
    lender,
    humaConfigContract,
    feeManagerContract,
    testTokenContract,
    principalRateInBps
) {
    await feeManagerContract.connect(poolOwner).setMinPrincipalRateInBps(principalRateInBps);

    const TransparentUpgradeableProxy = await ethers.getContractFactory(
        "TransparentUpgradeableProxy"
    );

    const HDT = await ethers.getContractFactory("HDT");
    const hdtImpl = await HDT.deploy();
    await hdtImpl.deployed();
    const hdtProxy = await TransparentUpgradeableProxy.deploy(
        hdtImpl.address,
        proxyOwner.address,
        []
    );
    await hdtProxy.deployed();
    hdtContract = HDT.attach(hdtProxy.address);
    await hdtContract.initialize("Base Credit HDT", "CHDT", testTokenContract.address);

    // Deploy BaseCreditPool
    const BaseCreditPool = await ethers.getContractFactory("BaseCreditPool");
    const poolImpl = await BaseCreditPool.deploy();
    await poolImpl.deployed();
    const poolProxy = await TransparentUpgradeableProxy.deploy(
        poolImpl.address,
        proxyOwner.address,
        []
    );
    await poolProxy.deployed();

    poolContract = BaseCreditPool.attach(poolProxy.address);
    await poolContract.initialize(
        hdtContract.address,
        humaConfigContract.address,
        feeManagerContract.address,
        "Base Credit Pool"
    );
    await poolContract.deployed();

    await hdtContract.setPool(poolContract.address);

    // Pool setup
    await poolContract.transferOwnership(poolOwner.address);

    await testTokenContract.connect(poolOwner).approve(poolContract.address, 100);
    await poolContract.connect(poolOwner).enablePool();
    await poolContract.connect(poolOwner).makeInitialDeposit(100);
    await poolContract.connect(poolOwner).setAPR(1217);
    await poolContract.connect(poolOwner).setMaxCreditLine(10000);
    await poolContract.connect(poolOwner).setEvaluationAgent(evaluationAgent.address);
    await testTokenContract.connect(lender).approve(poolContract.address, 10000);
    await poolContract.connect(lender).deposit(10000);

    return [hdtContract, poolContract];
}

module.exports = {
    deployContracts,
    deployAndSetupPool,
};