// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {WalletScoreTestBase} from "./WalletScoreTestBase.sol";
import {IWalletScore} from "src/WalletScore/IWalletScore.sol";
import {DomainId, ScoreSetId, PublisherId, ScoreSetStatus, ScoreSetMeta, Entry} from "src/WalletScore/Types.sol";

contract ScoreSetTest is WalletScoreTestBase {
    function setUp() public override {
        super.setUp();
        _registerDomainAvici();
        _registerAndFundPublisher1();
        _registerAndFundPublisher2();
    }

    // ============ Creation Tests ============

    function test_createScoreSet_Success() public {
        uint256 scoreTimestamp = block.timestamp;

        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, scoreTimestamp);

        ScoreSetMeta memory meta = ws.getScoreSetMeta(id);
        assertEq(DomainId.unwrap(meta.domainId), DomainId.unwrap(domainAvici));
        assertEq(PublisherId.unwrap(meta.publisher), PublisherId.unwrap(publisher1Id));
        assertEq(meta.scoreTimestamp, scoreTimestamp);
        assertEq(uint8(meta.status), uint8(ScoreSetStatus.Draft));
        assertEq(meta.minRank, 0);
        assertEq(meta.maxRank, 0);
    }

    function test_createScoreSet_AssignsIncrementingIds() public {
        ScoreSetId id1 = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        ScoreSetId id2 = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        ScoreSetId id3 = _createDraftScoreSetAsPublisher2(domainAvici, block.timestamp);

        assertEq(ScoreSetId.unwrap(id1), 1);
        assertEq(ScoreSetId.unwrap(id2), 2);
        assertEq(ScoreSetId.unwrap(id3), 3);
    }

    function test_createScoreSet_EmitsScoreSetCreated() public {
        vm.expectEmit(true, true, true, false);
        emit IWalletScore.ScoreSetCreated(ScoreSetId.wrap(1), domainAvici, publisher1Id);

        _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
    }

    function test_createScoreSet_RevertWhenNotPublisher() public {
        vm.prank(nobody);
        vm.expectRevert();
        ws.createScoreSet(domainAvici, block.timestamp);
    }

    function test_createScoreSet_RevertWhenDomainNotFound() public {
        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainNotFound.selector, domainUnregistered));
        ws.createScoreSet(domainUnregistered, block.timestamp);
    }

    // ============ Add Scores Tests ============

    function test_addScoresToScoreSet_Success() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(3);

        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);

        ScoreSetMeta memory meta = ws.getScoreSetMeta(id);
        assertEq(meta.minRank, 1);
        assertEq(meta.maxRank, 3);

        Entry memory entry = ws.getEntryAtRank(id, 1);
        assertEq(entry.wallet, entries[0].wallet);
        assertEq(entry.score, entries[0].score);
    }

    function test_addScoresToScoreSet_MultipleBatches() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);

        Entry[] memory batch1 = _buildSampleEntries(2);
        _addEntriesToScoreSet(id, publisher1Addr, 1, batch1);

        Entry[] memory batch2 = new Entry[](2);
        batch2[0] = Entry({wallet: address(0x2000), score: 500});
        batch2[1] = Entry({wallet: address(0x2001), score: 400});
        _addEntriesToScoreSet(id, publisher1Addr, 3, batch2);

        ScoreSetMeta memory meta = ws.getScoreSetMeta(id);
        assertEq(meta.minRank, 1);
        assertEq(meta.maxRank, 4);
    }

    function test_addScoresToScoreSet_RevertWhenNotOwner() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);

        vm.prank(publisher2Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.NotScoreSetOwner.selector, id));
        ws.addScoresToScoreSet(id, 1, entries);
    }

    function test_addScoresToScoreSet_RevertWhenScoreSetNotFound() public {
        Entry[] memory entries = _buildSampleEntries(2);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.ScoreSetNotFound.selector, ScoreSetId.wrap(999)));
        ws.addScoresToScoreSet(ScoreSetId.wrap(999), 1, entries);
    }

    function test_addScoresToScoreSet_RevertWhenInvalidStartRank() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InvalidRankRange.selector, 5, 2));
        ws.addScoresToScoreSet(id, 5, entries);
    }

    function test_addScoresToScoreSet_RevertWhenStartRankZero() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InvalidRankRange.selector, 0, 2));
        ws.addScoresToScoreSet(id, 0, entries);
    }

    function test_addScoresToScoreSet_RevertWhenEmptyEntries() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = new Entry[](0);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.InvalidRankRange.selector, 1, 0));
        ws.addScoresToScoreSet(id, 1, entries);
    }

    // ============ Publish Tests ============

    function test_publishScoreSet_Success() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(3);
        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);

        _publishScoreSet(id, publisher1Addr);

        ScoreSetMeta memory meta = ws.getScoreSetMeta(id);
        assertEq(uint8(meta.status), uint8(ScoreSetStatus.Published));
    }

    function test_publishScoreSet_EmitsScoreSetPublished() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(5);
        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);

        vm.expectEmit(true, false, false, true);
        emit IWalletScore.ScoreSetPublished(id, 5, 1, 5);

        _publishScoreSet(id, publisher1Addr);
    }

    function test_publishScoreSet_RevertWhenNotOwner() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);
        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);

        vm.prank(publisher2Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.NotScoreSetOwner.selector, id));
        ws.publishScoreSet(id);
    }

    function test_publishScoreSet_RevertWhenAlreadyPublished() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);
        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);
        _publishScoreSet(id, publisher1Addr);

        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.ScoreSetNotDraft.selector, id));
        ws.publishScoreSet(id);
    }

    function test_addScoresToScoreSet_RevertWhenAlreadyPublished() public {
        ScoreSetId id = _createDraftScoreSetAsPublisher1(domainAvici, block.timestamp);
        Entry[] memory entries = _buildSampleEntries(2);
        _addEntriesToScoreSet(id, publisher1Addr, 1, entries);
        _publishScoreSet(id, publisher1Addr);

        Entry[] memory moreEntries = _buildSampleEntries(2);
        vm.prank(publisher1Addr);
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.ScoreSetNotDraft.selector, id));
        ws.addScoresToScoreSet(id, 3, moreEntries);
    }

    // ============ Query Tests ============

    function test_getRankAndScore_Success() public {
        address wallet1 = address(0x1000);
        address wallet2 = address(0x1001);

        address[] memory wallets = new address[](2);
        wallets[0] = wallet1;
        wallets[1] = wallet2;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 9000;
        scores[1] = 8000;

        Entry[] memory entries = _buildEntriesWithWallets(wallets, scores);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        (uint256 rank1, uint256 score1) = ws.getRankAndScore(id, wallet1);
        assertEq(rank1, 1);
        assertEq(score1, 9000);

        (uint256 rank2, uint256 score2) = ws.getRankAndScore(id, wallet2);
        assertEq(rank2, 2);
        assertEq(score2, 8000);
    }

    function test_getRankAndScore_ReturnsZeroForUnknownWallet() public {
        Entry[] memory entries = _buildSampleEntries(2);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        (uint256 rank, uint256 score) = ws.getRankAndScore(id, address(0xDEAD));
        assertEq(rank, 0);
        assertEq(score, 0);
    }

    function test_getRanksAndScores_Success() public {
        address wallet1 = address(0x1000);
        address wallet2 = address(0x1001);
        address wallet3 = address(0x1002);

        address[] memory entryWallets = new address[](3);
        entryWallets[0] = wallet1;
        entryWallets[1] = wallet2;
        entryWallets[2] = wallet3;
        uint256[] memory entryScores = new uint256[](3);
        entryScores[0] = 9000;
        entryScores[1] = 8000;
        entryScores[2] = 7000;

        Entry[] memory entries = _buildEntriesWithWallets(entryWallets, entryScores);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        address[] memory queryWallets = new address[](3);
        queryWallets[0] = wallet2;
        queryWallets[1] = wallet1;
        queryWallets[2] = address(0xDEAD);

        (uint256[] memory ranks, uint256[] memory scores) = ws.getRanksAndScores(id, queryWallets);

        assertEq(ranks[0], 2);
        assertEq(scores[0], 8000);
        assertEq(ranks[1], 1);
        assertEq(scores[1], 9000);
        assertEq(ranks[2], 0);
        assertEq(scores[2], 0);
    }

    function test_getEntryAtRank_Success() public {
        Entry[] memory entries = _buildSampleEntries(3);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        Entry memory entry = ws.getEntryAtRank(id, 2);
        assertEq(entry.wallet, entries[1].wallet);
        assertEq(entry.score, entries[1].score);
    }

    function test_getEntryAtRank_RevertWhenRankOutOfRange() public {
        Entry[] memory entries = _buildSampleEntries(3);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        vm.expectRevert(abi.encodeWithSelector(IWalletScore.RankOutOfRange.selector, 5, 1, 3));
        ws.getEntryAtRank(id, 5);
    }

    function test_getEntriesInRankRange_Success() public {
        Entry[] memory entries = _buildSampleEntries(5);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        Entry[] memory result = ws.getEntriesInRankRange(id, 2, 3);

        assertEq(result.length, 3);
        assertEq(result[0].wallet, entries[1].wallet);
        assertEq(result[1].wallet, entries[2].wallet);
        assertEq(result[2].wallet, entries[3].wallet);
    }

    function test_getEntriesInRankRange_ClampsToValidRange() public {
        Entry[] memory entries = _buildSampleEntries(5);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        Entry[] memory result = ws.getEntriesInRankRange(id, 4, 10);

        assertEq(result.length, 2);
        assertEq(result[0].wallet, entries[3].wallet);
        assertEq(result[1].wallet, entries[4].wallet);
    }

    function test_getEntriesInRankRange_ReturnsEmptyWhenStartBeyondMax() public {
        Entry[] memory entries = _buildSampleEntries(3);
        ScoreSetId id = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, block.timestamp, entries);

        Entry[] memory result = ws.getEntriesInRankRange(id, 10, 5);

        assertEq(result.length, 0);
    }

    // ============ Latest Score Set Lookup Tests ============

    function test_getLatestScoreSetId_ReturnsLatestInWindow() public {
        uint256 ts1 = block.timestamp;
        uint256 ts2 = block.timestamp + 1 hours;
        uint256 ts3 = block.timestamp + 2 hours;

        Entry[] memory entries = _buildSampleEntries(2);
        _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, ts1, entries);
        ScoreSetId id2 = _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, ts2, entries);
        _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, ts3, entries);

        ScoreSetId found = ws.getLatestScoreSetId(domainAvici, ts1, ts2);

        assertEq(ScoreSetId.unwrap(found), ScoreSetId.unwrap(id2));
    }

    function test_getLatestScoreSetId_ReturnsZeroWhenNoneInWindow() public {
        uint256 ts = block.timestamp;

        Entry[] memory entries = _buildSampleEntries(2);
        _createAndPublishScoreSetWithEntries(publisher1Addr, domainAvici, ts, entries);

        ScoreSetId found = ws.getLatestScoreSetId(domainAvici, ts + 1 hours, ts + 2 hours);

        assertEq(ScoreSetId.unwrap(found), 0);
    }

    function test_getLatestScoreSetId_RevertWhenDomainNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IWalletScore.DomainNotFound.selector, domainUnregistered));
        ws.getLatestScoreSetId(domainUnregistered, block.timestamp, block.timestamp + 1 hours);
    }
}
