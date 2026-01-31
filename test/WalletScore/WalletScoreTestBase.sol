// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {WalletScoreV1} from "src/WalletScore/WalletScoreV1.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {
    DomainId,
    ScoreSetId,
    RequestId,
    PublisherId,
    BidId,
    BidSelection,
    RequestStatus,
    BidStatus,
    ScoreSetStatus,
    Publisher,
    ScoreSetMeta,
    Entry,
    ScoreRequest,
    Bid
} from "src/WalletScore/Types.sol";

abstract contract WalletScoreTestBase is Test {
    WalletScoreV1 public ws;

    // ============ Actors ============

    address internal admin = makeAddr("admin");
    address internal publisher1Addr = makeAddr("publisher1");
    address internal publisher2Addr = makeAddr("publisher2");
    address internal publisher3Addr = makeAddr("publisher3");
    address internal requester1 = makeAddr("requester1");
    address internal requester2 = makeAddr("requester2");
    address internal nobody = makeAddr("nobody");

    // ============ Domain IDs ============

    DomainId internal domainAvici = DomainId.wrap(keccak256("avici"));
    DomainId internal domainUniswap = DomainId.wrap(keccak256("uniswap"));
    DomainId internal domainUnregistered = DomainId.wrap(keccak256("unregistered"));

    // ============ Publisher IDs (set during setup) ============

    PublisherId internal publisher1Id;
    PublisherId internal publisher2Id;
    PublisherId internal publisher3Id;

    // ============ Constants ============

    uint256 internal constant DEFAULT_BOND = 1 ether;
    uint256 internal constant MIN_BOND = 0.1 ether;
    uint256 internal constant REQUESTER_BALANCE = 10 ether;

    string internal constant DOMAIN_METADATA = "ipfs://domain-metadata";
    string internal constant PUBLISHER_METADATA = "ipfs://publisher-metadata";

    // ============ Setup ============

    function setUp() public virtual {
        vm.warp(1 days + 1);
        _deployContract();
        _configureMinBond();
    }

    function _deployContract() internal {
        vm.startPrank(admin);
        address proxy =
            Upgrades.deployUUPSProxy("WalletScoreV1.sol:WalletScoreV1", abi.encodeCall(WalletScoreV1.initialize, ()));
        ws = WalletScoreV1(proxy);
        vm.stopPrank();
    }

    function _configureMinBond() internal {
        vm.prank(admin);
        ws.setMinPublisherBond(MIN_BOND);
    }

    // ============ Domain Setup Helpers ============

    function _registerDomainAvici() internal {
        vm.prank(admin);
        ws.registerDomain(domainAvici, DOMAIN_METADATA);
    }

    function _registerDomainUniswap() internal {
        vm.prank(admin);
        ws.registerDomain(domainUniswap, DOMAIN_METADATA);
    }

    function _registerBothDomains() internal {
        _registerDomainAvici();
        _registerDomainUniswap();
    }

    // ============ Publisher Setup Helpers ============

    function _registerPublisher1() internal {
        vm.prank(admin);
        publisher1Id = ws.registerPublisher(publisher1Addr, PUBLISHER_METADATA);
    }

    function _registerPublisher2() internal {
        vm.prank(admin);
        publisher2Id = ws.registerPublisher(publisher2Addr, PUBLISHER_METADATA);
    }

    function _registerPublisher3() internal {
        vm.prank(admin);
        publisher3Id = ws.registerPublisher(publisher3Addr, PUBLISHER_METADATA);
    }

    function _registerAllPublishers() internal {
        _registerPublisher1();
        _registerPublisher2();
        _registerPublisher3();
    }

    function _fundAndDepositBondForPublisher1() internal {
        _fundAndDepositBondForPublisher1(DEFAULT_BOND);
    }

    function _fundAndDepositBondForPublisher1(uint256 amount) internal {
        vm.deal(publisher1Addr, amount);
        vm.prank(publisher1Addr);
        ws.depositBond{value: amount}();
    }

    function _fundAndDepositBondForPublisher2() internal {
        _fundAndDepositBondForPublisher2(DEFAULT_BOND);
    }

    function _fundAndDepositBondForPublisher2(uint256 amount) internal {
        vm.deal(publisher2Addr, amount);
        vm.prank(publisher2Addr);
        ws.depositBond{value: amount}();
    }

    function _fundAndDepositBondForPublisher3() internal {
        _fundAndDepositBondForPublisher3(DEFAULT_BOND);
    }

    function _fundAndDepositBondForPublisher3(uint256 amount) internal {
        vm.deal(publisher3Addr, amount);
        vm.prank(publisher3Addr);
        ws.depositBond{value: amount}();
    }

    function _registerAndFundPublisher1() internal {
        _registerPublisher1();
        _fundAndDepositBondForPublisher1();
    }

    function _registerAndFundPublisher2() internal {
        _registerPublisher2();
        _fundAndDepositBondForPublisher2();
    }

    function _registerAndFundPublisher3() internal {
        _registerPublisher3();
        _fundAndDepositBondForPublisher3();
    }

    function _registerAndFundAllPublishers() internal {
        _registerAndFundPublisher1();
        _registerAndFundPublisher2();
        _registerAndFundPublisher3();
    }

    // ============ Requester Setup Helpers ============

    function _fundRequester1() internal {
        vm.deal(requester1, REQUESTER_BALANCE);
    }

    function _fundRequester2() internal {
        vm.deal(requester2, REQUESTER_BALANCE);
    }

    function _fundAllRequesters() internal {
        _fundRequester1();
        _fundRequester2();
    }

    // ============ Full Fixture Helpers ============

    function _setupBasicFixture() internal {
        _registerDomainAvici();
        _registerAndFundPublisher1();
        _fundRequester1();
    }

    function _setupFullFixture() internal {
        _registerBothDomains();
        _registerAndFundAllPublishers();
        _fundAllRequesters();
    }

    // ============ Score Set Helpers ============

    function _createDraftScoreSetAsPublisher1(DomainId domainId, uint256 scoreTimestamp) internal returns (ScoreSetId) {
        vm.prank(publisher1Addr);
        return ws.createScoreSet(domainId, scoreTimestamp);
    }

    function _createDraftScoreSetAsPublisher2(DomainId domainId, uint256 scoreTimestamp) internal returns (ScoreSetId) {
        vm.prank(publisher2Addr);
        return ws.createScoreSet(domainId, scoreTimestamp);
    }

    function _addEntriesToScoreSet(ScoreSetId scoreSetId, address publisher, uint256 startRank, Entry[] memory entries)
        internal
    {
        vm.prank(publisher);
        ws.addScoresToScoreSet(scoreSetId, startRank, entries);
    }

    function _publishScoreSet(ScoreSetId scoreSetId, address publisher) internal {
        vm.prank(publisher);
        ws.publishScoreSet(scoreSetId);
    }

    function _createAndPublishScoreSetWithEntries(
        address publisher,
        DomainId domainId,
        uint256 scoreTimestamp,
        Entry[] memory entries
    ) internal returns (ScoreSetId) {
        vm.startPrank(publisher);
        ScoreSetId id = ws.createScoreSet(domainId, scoreTimestamp);
        ws.addScoresToScoreSet(id, 1, entries);
        ws.publishScoreSet(id);
        vm.stopPrank();
        return id;
    }

    function _buildSampleEntries(uint256 count) internal pure returns (Entry[] memory) {
        Entry[] memory entries = new Entry[](count);
        for (uint256 i = 0; i < count; i++) {
            entries[i] = Entry({wallet: address(uint160(0x1000 + i)), score: (count - i) * 1000});
        }
        return entries;
    }

    function _buildEntriesWithWallets(address[] memory wallets, uint256[] memory scores)
        internal
        pure
        returns (Entry[] memory)
    {
        require(wallets.length == scores.length, "length mismatch");
        Entry[] memory entries = new Entry[](wallets.length);
        for (uint256 i = 0; i < wallets.length; i++) {
            entries[i] = Entry({wallet: wallets[i], score: scores[i]});
        }
        return entries;
    }

    // ============ Request Helpers ============

    function _createWalletRequest(
        address requester,
        DomainId domainId,
        address[] memory wallets,
        uint256 minTs,
        uint256 maxTs,
        uint256 quotingDeadline,
        uint256 fulfillmentDeadline,
        uint256 budget
    ) internal returns (RequestId) {
        vm.prank(requester);
        return ws.createRequest{value: budget}(
            domainId,
            wallets,
            0, // startRank (unused for wallet requests)
            0, // rankCount (unused for wallet requests)
            minTs,
            maxTs,
            quotingDeadline,
            fulfillmentDeadline,
            BidSelection.Cheapest
        );
    }

    function _createRankRangeRequest(
        address requester,
        DomainId domainId,
        uint256 startRank,
        uint256 rankCount,
        uint256 minTs,
        uint256 maxTs,
        uint256 quotingDeadline,
        uint256 fulfillmentDeadline,
        uint256 budget
    ) internal returns (RequestId) {
        vm.prank(requester);
        return ws.createRequest{value: budget}(
            domainId,
            new address[](0),
            startRank,
            rankCount,
            minTs,
            maxTs,
            quotingDeadline,
            fulfillmentDeadline,
            BidSelection.Cheapest
        );
    }

    function _createSimpleRequest(uint256 budget) internal returns (RequestId) {
        uint256 quotingDeadline = block.timestamp + 1 hours;
        uint256 fulfillmentDeadline = block.timestamp + 2 hours;

        address[] memory wallets = new address[](1);
        wallets[0] = address(0x1000);

        return _createWalletRequest(
            requester1,
            domainAvici,
            wallets,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            quotingDeadline,
            fulfillmentDeadline,
            budget
        );
    }

    // ============ Bid Helpers ============

    function _submitBidAsPublisher1(RequestId requestId, uint256 price, uint256 promisedDuration)
        internal
        returns (BidId)
    {
        vm.prank(publisher1Addr);
        return ws.submitBid(requestId, price, promisedDuration);
    }

    function _submitBidAsPublisher2(RequestId requestId, uint256 price, uint256 promisedDuration)
        internal
        returns (BidId)
    {
        vm.prank(publisher2Addr);
        return ws.submitBid(requestId, price, promisedDuration);
    }

    function _submitBidAsPublisher3(RequestId requestId, uint256 price, uint256 promisedDuration)
        internal
        returns (BidId)
    {
        vm.prank(publisher3Addr);
        return ws.submitBid(requestId, price, promisedDuration);
    }

    // ============ Time Helpers ============

    function _advancePastQuotingDeadline(RequestId requestId) internal {
        ScoreRequest memory req = ws.getRequest(requestId);
        vm.warp(req.quotingDeadline + 1);
    }

    function _advanceToJustBeforeQuotingDeadline(RequestId requestId) internal {
        ScoreRequest memory req = ws.getRequest(requestId);
        vm.warp(req.quotingDeadline - 1);
    }

    function _advancePastBidDeadline(BidId bidId) internal {
        Bid memory bid = ws.getBid(bidId);
        vm.warp(bid.selectedAt + bid.promisedDuration + 1);
    }

    function _advancePastFulfillmentDeadline(RequestId requestId) internal {
        ScoreRequest memory req = ws.getRequest(requestId);
        vm.warp(req.fulfillmentDeadline + 1);
    }

    // ============ Assertion Helpers ============

    function _assertRequestStatus(RequestId requestId, RequestStatus expected) internal view {
        ScoreRequest memory req = ws.getRequest(requestId);
        assertEq(uint8(req.status), uint8(expected), "unexpected request status");
    }

    function _assertBidStatus(BidId bidId, BidStatus expected) internal view {
        Bid memory bid = ws.getBid(bidId);
        assertEq(uint8(bid.status), uint8(expected), "unexpected bid status");
    }

    function _assertPublisherBond(PublisherId publisherId, uint256 expected) internal view {
        assertEq(ws.getPublisherBond(publisherId), expected, "unexpected bond balance");
    }

    function _assertWithdrawable(address addr, uint256 expected) internal view {
        assertEq(ws.getWithdrawable(addr), expected, "unexpected withdrawable balance");
    }

    function _assertTreasuryBalance(uint256 expected) internal view {
        assertEq(ws.getTreasuryBalance(), expected, "unexpected treasury balance");
    }

    // ============ Utility ============

    function _singleWalletArray(address wallet) internal pure returns (address[] memory) {
        address[] memory wallets = new address[](1);
        wallets[0] = wallet;
        return wallets;
    }

    function _twoWalletArray(address wallet1, address wallet2) internal pure returns (address[] memory) {
        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        return wallets;
    }
}
