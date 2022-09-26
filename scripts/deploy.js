const {ethers} = require("hardhat");

async function deployContracts() {
    // Deploy HumaConfig
    [owner, proxyOwner, lender, borrower, treasury, evaluationAgent] = await ethers.getSigners();
    const HumaConfig = await ethers.getContractFactory("HumaConfig");
    let humaConfigContract = await HumaConfig.deploy(treasury.address);
    await humaConfigContract.setHumaTreasury(treasury.address);
    console.log("\n**********************************:");
    console.log("HumaConfig deployed to:", humaConfigContract.address);

    // Deploy Fee Manager
    const feeManagerFactory = await ethers.getContractFactory("BaseFeeManager");
    let feeManager = await feeManagerFactory.deploy();
    console.log("Fee Manager deployed to:", feeManager.address);
    await feeManager.connect(owner).setFees(10, 100, 20, 500, 0);
    await feeManager.connect(owner).setMinPrincipalRateInBps(500);
    console.log("Fees are set to 10, 100, 20, 500");
    console.log("PrincipalRateInBps is set to 500");

    // Deploy TestToken, give initial tokens to lender
    const TestToken = await ethers.getContractFactory("TestToken");
    let testToken = await TestToken.deploy();
    console.log("TestToken deployed to:", feeManager.address);
    await testToken.give1000To(lender.address);
    console.log("1000 test token dropped to:", lender.address);
    await testToken.give1000To(owner.address);
    console.log("1000 test token dropped to:", owner.address);

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
    await hdtContract.initialize("Base HDT", "BHDT", testToken.address);
    console.log("hdt contract deployed to:", hdtContract.address);

    const BasePoolConfig = await ethers.getContractFactory("BasePoolConfig");
    const poolConfig = await BasePoolConfig.deploy(
        "Base Credit Pool",
        hdtContract.address,
        humaConfigContract.address,
        feeManager.address
    );
    await poolConfig.deployed();

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

    console.log("poolProxy deployed to:", poolProxy.address);

    let poolContract = BaseCreditPool.attach(poolProxy.address);
    await poolContract.connect(owner).initialize(poolConfig.address);

    console.log("BaseCreditPool deployed to:", poolContract.address);
    await poolConfig.setPool(poolContract.address);
    await hdtContract.setPool(poolContract.address);

    // Pool setup
    await testToken.connect(owner).approve(poolContract.address, 100);
    await poolContract.connect(owner).addApprovedLender(owner.address);
    await poolContract.connect(owner).addApprovedLender(lender.address);
    await poolContract.connect(owner).makeInitialDeposit(100);
    await poolContract.enablePool();
    await poolConfig.connect(owner).setAPR(1217);
    await poolConfig.setMaxCreditLine(10_000_000);
    await poolConfig.setEvaluationAgent(1, evaluationAgent.address);
    await testToken.connect(lender).approve(poolContract.address, 10000);
    await poolContract.connect(lender).deposit(10000);
}

deployContracts()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
