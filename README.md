## Fund Splitter

FundSplitter is a tool designed to distribute funds among a group of users, such as DAO members, based on a predetermined ratio. Unlike standard bulk transfers, FundSplitter offers several unique features:

1. FundSplitter establishes a unified collection account (referred to hereafter as the Splitter Account) for the team. This eliminates the need for the fund issuer to use a bulk transfer tool; they can instead directly transfer funds into the Splitter Account, and FundSplitter handles the distribution.

2. The Splitter Account is keyless. After the system stabilizes, FundSplitter revokes the deployer's keys, rendering the Splitter Account completely decentralized.

3. FundSplitter issues a FLOAT to each group member. This FLOAT acts as a share certificate, documenting their distribution ratio. During the creation of the Splitter Account, it can be determined whether these FLOATs are transferable. If they are, group members can freely sell or transfer their distribution rights.

4. One Splitter Account can serve as a shareholder of another Splitter Account, offering flexibility in managing distribution rights.

### Architecture

![Structure](./assets/structure.jpg)