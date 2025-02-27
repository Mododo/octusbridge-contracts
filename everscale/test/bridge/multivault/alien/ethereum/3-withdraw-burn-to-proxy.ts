import {Ed25519KeyPair} from "nekoton-wasm";
import {Contract} from "locklift";
import {
    BridgeAbi,
    CellEncoderStandaloneAbi,
    EthereumEverscaleEventConfigurationAbi,
    EverscaleEthereumEventConfigurationAbi,
    EverscaleSolanaEventConfigurationAbi,
    SolanaEverscaleEventConfigurationAbi,
    ProxyMultiVaultAlien_V6Abi,
    StakingMockupAbi, TokenRootAlienEVMAbi, AlienTokenWalletUpgradeableAbi, MultiVaultEverscaleEVMEventAlienAbi
} from "../../../../../build/factorySource";
import {Account} from "everscale-standalone-client/nodejs";
import {setupBridge, setupRelays} from "../../../../utils/bridge";
import {deployAccount} from "../../../../utils/account";
import {logContract} from "../../../../utils/logger";
import {setupAlienMultiVault} from "../../../../utils/multivault/alien";
import {expect} from "chai";
import {EventAction, EventType, processEvent} from "../../../../utils/events";
import exp from "constants";
const logger = require("mocha-logger");


let relays: Ed25519KeyPair[];
let bridge: Contract<BridgeAbi>;
let cellEncoder: Contract<CellEncoderStandaloneAbi>;
let staking: Contract<StakingMockupAbi>;
let bridgeOwner: Account;

let ethereumEverscaleEventConfiguration: Contract<EthereumEverscaleEventConfigurationAbi>;
let everscaleEthereumEventConfiguration: Contract<EverscaleEthereumEventConfigurationAbi>;
let solanaEverscaleEventConfiguration: Contract<SolanaEverscaleEventConfigurationAbi>;
let everscaleSolanaEventConfiguration: Contract<EverscaleSolanaEventConfigurationAbi>;
let initializer: Account;
let proxy: Contract<ProxyMultiVaultAlien_V6Abi>;

let alienTokenRoot: Contract<TokenRootAlienEVMAbi>;
let initializerAlienTokenWallet: Contract<AlienTokenWalletUpgradeableAbi>;
let eventContract: Contract<MultiVaultEverscaleEVMEventAlienAbi>;


describe('Withdraw tokens by burning in favor of proxy', async function() {
    this.timeout(10000000);

    const alienTokenBase = {
        chainId: 111,
        token: 222,
    };

    const alienTokenMeta = {
        name: 'Giga Chad',
        symbol: 'GIGA_CHAD',
        decimals: 6,
    };

    const mintAmount = 1000;
    const amount = 333;
    const recipient = 888;

    it("Setup bridge", async () => {
        relays = await setupRelays();
        [bridge, bridgeOwner, staking, cellEncoder] = await setupBridge(relays);

        const signer = (await locklift.keystore.getSigner("0"))!;

        initializer = await deployAccount(signer, 50);

        await logContract("Initializer", initializer.address);

        [
            ethereumEverscaleEventConfiguration,
            everscaleEthereumEventConfiguration,
            solanaEverscaleEventConfiguration,
            everscaleSolanaEventConfiguration,
            proxy
        ] = await setupAlienMultiVault(bridgeOwner, staking);
    });

    it('Deploy alien token root', async () => {
        await proxy.methods.deployEVMAlienToken({
            ...alienTokenBase,
            ...alienTokenMeta,
            remainingGasTo: initializer.address
        }).send({
            from: initializer.address,
            amount: locklift.utils.toNano(5),
        });

        const alienTokenRootAddress = await proxy.methods.deriveEVMAlienTokenRoot({
            ...alienTokenBase,
            ...alienTokenMeta,
            answerId: 0
        }).call();

        alienTokenRoot = await locklift.factory.getDeployedContract(
            'TokenRootAlienEVM',
            alienTokenRootAddress.value0
        );

        await logContract("Alien token root", alienTokenRoot.address);
    });

    it('Mint tokens to the initializer', async () => {
        await proxy.methods.mint({
            amount: mintAmount,
            recipient: initializer.address,
            payload: '',
            token: alienTokenRoot.address
        }).send({
            from: bridgeOwner.address,
            amount: locklift.utils.toNano(2)
        });
    });

    it('Check initializer token balance', async () => {
        const walletAddress = await alienTokenRoot.methods.walletOf({
            answerId: 0,
            walletOwner: initializer.address
        }).call();

        initializerAlienTokenWallet = await locklift.factory.getDeployedContract(
            'AlienTokenWalletUpgradeable',
            walletAddress.value0
        );

        const balance = await initializerAlienTokenWallet.methods.balance({
            answerId: 0
        }).call();

        expect(Number(balance.value0))
            .to.be.equal(mintAmount, 'Wrong initializer token balance after mint')
    });

    it('Burn tokens in favor of proxy', async () => {
        const burnPayload = await cellEncoder.methods.encodeAlienBurnPayloadEthereum({
            recipient,
            callback: {
                recipient: 0,
                strict: false,
                payload: ''
            }
        }).call();

        const tx = await initializerAlienTokenWallet.methods.burn({
            amount,
            remainingGasTo: initializer.address,
            callbackTo: proxy.address,
            payload: burnPayload.value0
        }).send({
            from: initializer.address,
            amount: locklift.utils.toNano(10)
        });

        logger.log(`Event initialization tx: ${tx.id.hash}`);

        const events = await everscaleEthereumEventConfiguration
            .getPastEvents({ filter: "NewEventContract" })
            .then((e) => e.events);

        expect(events).to.have.lengthOf(
            1,
            "Everscale event configuration failed to deploy event"
        );

        const [
            {
                data: {
                    eventContract: expectedEventContract
                },
            },
        ] = events;

        logger.log(`Expected event address: ${expectedEventContract}`);

        eventContract = await locklift.factory.getDeployedContract(
            "MultiVaultEverscaleEVMEventAlien",
            expectedEventContract
        );
    });

    it("Check event contract exists", async () => {
        expect(
            Number(await locklift.provider.getBalance(eventContract.address))
        ).to.be.greaterThan(0, "Event contract balance is zero");
    });

    it('Check total supply reduced', async () => {
        const totalSupply = await alienTokenRoot.methods.totalSupply({
            answerId: 0
        }).call();

        expect(Number(totalSupply.value0))
            .to.be.equal(mintAmount - amount, 'Wrong total supply after burn');
    });

    it('Check initializer token balance reduced', async () => {
        const balance = await initializerAlienTokenWallet.methods.balance({
            answerId: 0
        }).call();

        expect(Number(balance.value0))
            .to.be.equal(mintAmount - amount, 'Wrong initializer token balance after burn')
    });

    it('Check event data after mutation', async () => {
        const decodedData = await eventContract.methods.getDecodedData({
            answerId: 0
        }).call();

        expect(Number(decodedData.base_token_))
            .to.be.equal(alienTokenBase.token, 'Wrong alien base token');
        expect(Number(decodedData.base_chainId_))
            .to.be.equal(alienTokenBase.chainId, 'Wrong alien base chain id');

        const eventInitData = await eventContract.methods.getEventInitData({
            answerId: 0,
        }).call();

        const decodedEventData = await cellEncoder.methods.decodeMultiVaultAlienEverscaleEthereum({
            data: eventInitData.value0.voteData.eventData
        }).call();

        expect(Number(decodedEventData.base_token))
            .to.be.equal(alienTokenBase.token, 'Wrong event data base token');
        expect(Number(decodedEventData.base_chainId))
            .to.be.equal(alienTokenBase.chainId, 'Wrong event data base chain id');
        expect(Number(decodedEventData.amount))
            .to.be.equal(amount, 'Wrong event data amount');
        expect(Number(decodedEventData.recipient))
            .to.be.equal(recipient, 'Wrong event data recipient');
    });

    it('Confirm event', async () => {
        await processEvent(
            relays,
            eventContract.address,
            EventType.EverscaleEthereum,
            EventAction.Confirm
        );
    });

    it('Close event', async () => {
        const balance = await locklift.provider.getBalance(eventContract.address);

        const { traceTree } = await locklift.tracing.trace(
            eventContract.methods.close().send({
                from: initializer.address,
                amount: locklift.utils.toNano(0.1)
            })
        );

        expect(Number(await locklift.provider.getBalance(eventContract.address)))
            .to.be.equal(0, 'Event contract balance should be 0 after close');

        expect(Number(traceTree?.getBalanceDiff(initializer.address)))
            .to.be.greaterThan(
                Number(balance) - Number(locklift.utils.toNano(1)), // Greater than balance - 1 ton for fees
            "Initializer should get money back after close"
            );
    });
});
