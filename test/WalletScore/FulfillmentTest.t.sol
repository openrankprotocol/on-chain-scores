// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
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
    ScoreRequest,
    Bid,
    Entry
} from "src/WalletScore/Types.sol";

contract FulfillmentTest is WalletScoreTestBase {
    RequestId internal requestId;
    BidId internal bidId;
    ScoreSetId internal scoreSetId;

    address internal wallet1 = address(0x1000);
    address internal wallet2 = address(0x1001);

    function setUp() public override {
        super.setUp();
        _setupFullFixture();
        _createRequestAndSelectBid();
        _createMatchingScoreSet();
    }

    function _createRequestAndSelectBid() internal {
        address[] memory wallets = _twoWalletArray(wallet1, wallet2);

        vm.prank(requester1);
        requestId = ws.createRequest{value: 1 ether}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            BidSelection.Cheapest
        );

        bidId = _submitBidAsPublisher1(requestId, 0.5 ether, 30 minutes);

        _advancePastQuotingDeadline(requestId);
        ws.advanceRequest(requestId);
    }

    function _createMatchingScoreSet() internal {
        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 9000;
        scores[1] = 8000;

        Entry[] memory entries = _buildEntriesWithWallets(wallets, scores);
        scoreSetId = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);
    }

    // ============ Happy Path Tests ============

    function test_fulfillRequest_Success() public {
        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        _assertRequestStatus(requestId, RequestStatus.Fulfilled);
        _assertBidStatus(bidId, BidStatus.Won);
    }

    function test_fulfillRequest_EmitsRequestFulfilled() public {
        vm.expectEmit(true, true, true, true);
        emit IWalletScore.RequestFulfilled(requestId, scoreSetId, publisher1Id, 0.5 ether);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);
    }

    function test_fulfillRequest_PaysPublisher() public {
        uint256 withdrawableBefore = ws.getWithdrawable(publisher1Addr);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        assertEq(ws.getWithdrawable(publisher1Addr), withdrawableBefore + 0.5 ether);
    }

    function test_fulfillRequest_RefundsExcessToRequester() public {
        uint256 withdrawableBefore = ws.getWithdrawable(requester1);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        assertEq(ws.getWithdrawable(requester1), withdrawableBefore + 0.5 ether);
    }

    function test_fulfillRequest_ReleasesOtherBidders() public {
        requestId = _createNewRequestWithMultipleBids();

        Entry[] memory entries = _buildSampleEntries(2);
        entries[0].wallet = wallet1;
        entries[1].wallet = wallet2;
        ScoreSetId newScoreSet =
            _createAndPublishScoreSetWithEntries(publisher2Addr, domainAvici, block.timestamp, entries);

        ScoreRequest memory req = ws.getRequest(requestId);

        vm.prank(publisher2Addr);
        ws.fulfillRequest(requestId, newScoreSet);

        BidId[] memory allBids = ws.getRequestBids(requestId);
        for (uint256 i = 0; i < allBids.length; i++) {
            Bid memory bid = ws.getBid(allBids[i]);
            if (BidId.unwrap(allBids[i]) == BidId.unwrap(req.currentBid)) {
                assertEq(uint8(bid.status), uint8(BidStatus.Won));
            } else {
                assertEq(uint8(bid.status), uint8(BidStatus.Superseded));
            }
        }
    }

    function test_fulfillRequest_DecrementsPublisherActiveBidCount() public {
        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        vm.prank(publisher1Addr);
        ws.withdrawBond(DEFAULT_BOND);
    }

    // ============ Rank Range Request Fulfillment ============

    function test_fulfillRequest_RankRangeRequest() public {
        RequestId rankRequest = _createRankRangeRequest(
            requester1,
            domainAvici,
            1,
            5,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            1 ether
        );

        _submitBidAsPublisher1(rankRequest, 0.5 ether, 30 minutes);
        _advancePastQuotingDeadline(rankRequest);
        ws.advanceRequest(rankRequest);

        Entry[] memory entries = _buildSampleEntries(10);
        ScoreSetId rankScoreSet =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.prank(publisher1Addr);
        ws.fulfillRequest(rankRequest, rankScoreSet);

        _assertRequestStatus(rankRequest, RequestStatus.Fulfilled);
    }

    // ============ Validation Error Tests ============

    function test_fulfillRequest_RevertWhenNotAssigned() public {
        RequestId newRequest = _createSimpleRequest(1 ether);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.RequestNotAssigned.selector, newRequest, RequestStatus.Quoting)
        );
        ws.fulfillRequest(newRequest, scoreSetId);
    }

    function test_fulfillRequest_RevertWhenNotCurrentBidder() public {
        vm.prank(publisher2Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.NotCurrentBidder.selector, requestId, publisher2Id, publisher1Id)
        );
        ws.fulfillRequest(requestId, scoreSetId);
    }

    function test_fulfillRequest_RevertWhenDeadlineExceeded() public {
        _advancePastBidDeadline(bidId);

        vm.prank(publisher1Addr);
        vm.expectRevert();
        ws.fulfillRequest(requestId, scoreSetId);
    }

    function test_fulfillRequest_RevertWhenDomainMismatch() public {
        Entry[] memory entries = _buildSampleEntries(2);
        ScoreSetId wrongDomainSet =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainUniswap, block.timestamp, entries);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.ScoreSetDoesNotCoverRequest.selector, wrongDomainSet, requestId)
        );
        ws.fulfillRequest(requestId, wrongDomainSet);
    }

    function test_fulfillRequest_RevertWhenScoreSetNotPublished() public {
        vm.prank(publisher1Addr);
        ScoreSetId draftSet = ws.createScoreSet(domainAvici, block.timestamp);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.ScoreSetDoesNotCoverRequest.selector, draftSet, requestId));
        ws.fulfillRequest(requestId, draftSet);
    }

    function test_fulfillRequest_RevertWhenTimestampOutOfRange() public {
        Entry[] memory entries = _buildSampleEntries(2);
        entries[0].wallet = wallet1;
        entries[1].wallet = wallet2;

        ScoreSetId futureSet =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp + 2 days, entries);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.ScoreSetDoesNotCoverRequest.selector, futureSet, requestId));
        ws.fulfillRequest(requestId, futureSet);
    }

    function test_fulfillRequest_RevertWhenMissingWallet() public {
        address[] memory wallets = new address[](1);
        wallets[0] = wallet1;

        uint256[] memory scores = new uint256[](1);
        scores[0] = 9000;

        Entry[] memory entries = _buildEntriesWithWallets(wallets, scores);
        ScoreSetId incompleteSet =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.ScoreSetDoesNotCoverRequest.selector, incompleteSet, requestId)
        );
        ws.fulfillRequest(requestId, incompleteSet);
    }

    function test_fulfillRequest_RevertWhenRankRangeNotCovered() public {
        RequestId rankRequest = _createRankRangeRequest(
            requester1,
            domainAvici,
            1,
            10,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            1 ether
        );

        _submitBidAsPublisher1(rankRequest, 0.5 ether, 30 minutes);
        _advancePastQuotingDeadline(rankRequest);
        ws.advanceRequest(rankRequest);

        Entry[] memory entries = _buildSampleEntries(5);
        ScoreSetId smallSet =
            _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.prank(publisher1Addr);
        vm.expectRevert(
            abi.encodeWithSelector(IWalletScore.ScoreSetDoesNotCoverRequest.selector, smallSet, rankRequest)
        );
        ws.fulfillRequest(rankRequest, smallSet);
    }

    // ============ Withdrawal Tests ============

    function test_withdraw_Success() public {
        vm.prank(publisher1Addr);
        ws.fulfillRequest(requestId, scoreSetId);

        uint256 withdrawable = ws.getWithdrawable(publisher1Addr);
        uint256 balanceBefore = publisher1Addr.balance;

        vm.prank(publisher1Addr);
        ws.withdraw();

        assertEq(publisher1Addr.balance, balanceBefore + withdrawable);
        assertEq(ws.getWithdrawable(publisher1Addr), 0);
    }

    function test_withdraw_NoOpWhenZeroBalance() public {
        uint256 balanceBefore = nobody.balance;

        vm.prank(nobody);
        ws.withdraw();

        assertEq(nobody.balance, balanceBefore);
    }

    // ============ Helpers ============

    function _createNewRequestWithMultipleBids() internal returns (RequestId) {
        address[] memory wallets = _twoWalletArray(wallet1, wallet2);

        vm.prank(requester2);
        RequestId newReq = ws.createRequest{value: 1 ether}(
            domainAvici,
            wallets,
            0,
            0,
            block.timestamp - 1 days,
            block.timestamp + 1 days,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            BidSelection.Cheapest
        );

        _submitBidAsPublisher1(newReq, 0.5 ether, 30 minutes);
        _submitBidAsPublisher2(newReq, 0.3 ether, 30 minutes);
        _submitBidAsPublisher3(newReq, 0.7 ether, 30 minutes);

        _advancePastQuotingDeadline(newReq);
        ws.advanceRequest(newReq);

        return newReq;
    }
}
