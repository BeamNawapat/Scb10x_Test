const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Greeter", function () {
    it("Should return the new greeting once it's changed", async function () {
        // const Greeter = await ethers.getContractFactory("Greeter");
        // const greeter = await Greeter.deploy("Hello, world!");
        // await greeter.deployed();

        // expect(await greeter.greet()).to.equal("Hello, world!");

        // const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

        // // wait until the transaction is mined
        // await setGreetingTx.wait();

        // expect(await greeter.greet()).to.equal("Hola, mundo!");

        // const provider = new ethers.providers.JsonRpcProvider();
        // const signer = await provider.getSigner();
        // const accounts = await signer.getAddress();
        // console.log(accounts)

            //  const accounts = await hre.ethers.getSigners();
            //  const MyContract = await ethers.getContractFactory("MyContract");
            //  const myContract = new ethers.Contract(
            //      MyContract,
            //      MyContract.interface,
            //      accounts[0]
            //  );
    });
});
