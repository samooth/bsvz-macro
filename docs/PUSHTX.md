# PUSHTX and its Building Blocks

Source: https://nchain.com/wp-content/uploads/2022/03/WP1605_PUSHTX-and-its-Building-Blocks.pdf

## Extracted Content

PUSHTX and its Building Blocks
White Paper
WP1605
Created:
Last updated:

20/05/2021
14/12/2021

PUSHTX and Its Building Blocks

Copyright
Information in this document is subject to change without notice and is furnished under a
license agreement or nondisclosure agreement. The information may only be used or copied in
accordance with the terms of those agreements.
All rights reserved. No part of this publication may be reproduced, stored in a retrieval system,
or transmitted in any form or any means electronic or mechanical, including photocopying and
recording for any purpose other than the purchaser’s personal use without the written
permission of nChain Licensing AG. The names of actual companies and products mentioned in
this document may be trademarks of their respective owners. nChain Licensing AG accepts no
responsibility or liability for any errors or inaccuracies that may appear in this documentation.

Disclaimer
The information contained herein, such as code, data structures, pseudo-code, etc. is provided
“as is”, no warranty, express or implied, regarding the merchantability or fitness for purpose of
the information contained herein, is provided by nChain Licensing AG or any of its group
companies. Neither nChain Licensing AG, nor any of its group companies, accepts any liability
for any consequential, incidental, special or indirect damages that may occur through use of the
information contained herein.

Authors
Name

Title

Wei Zhang

Principal Researcher

WP1605

© nChain Licensing AG

2 of 25

PUSHTX and Its Building Blocks

Contents
1

PUSHTX and Its Building Blocks ..................................................................................... 4

1.1

Generating the signature in-script ...................................................................... 4

1.2

Constructing the message in-script ....................................................................5

1.3

Example of a PELS .................................................................................................... 8

1.4

Optimisation ................................................................................................................ 12

2

Security Analysis .................................................................................................................. 15

3

Appendix ................................................................................................................................. 18

WP1605

© nChain Licensing AG

3 of 25

PUSHTX and Its Building Blocks

1

PUSHTX and Its Building Blocks

The core idea of PUSHTX (originally invented by Y. Chan and D. Kramer at nChain in 2017) is to
generate a signature in-script on a data element on the stack and call OP_CHECKSIG to verify
the signature. If it passes, it implies that the message constructed by OP_CHECKSIG is identical
to the data element pushed to the stack. Therefore, it achieves the effect of pushing the
current spending transaction to the stack. Since its adoption by sCrypt, STAS token and
Sensible Contracts, the PUSHTX idea has been widely discussed and tested in practice. The
purpose of this document is to offer some security insight and optimisations while revisiting
PUSHTX with an example of a perpetually enforcing locking script. We focus on two most
important building blocks of PUSHTX, the signature generation and the message construction.
The size of its spending transaction is intended to be a benchmark for reference. Other
techniques of pushing transactions to the stack are out of scope of this white paper.
A perpetually enforcing locking script (PELS) is a locking script that enforces some condition or
conditions on all future transactions in the spending chain that originates from the output that
contains this locking script. One example to achieve this is to design a locking script that forces
the locking script in the spending transaction to be the same as itself. Note that a locking script
with an enforcement only on the next spending transaction would have a much simpler design.
PELS are particularly useful for the sender (originator) as they can be ensured that all future
spending transactions will follow the rules which they set out in the locking script. Any violation
of the rules would invalidate the transaction in terms of script execution.

1.1 Generating the signature in-script
The first building block is to generate the signature for a given message 𝑚. We assume that the
following script segment is part of a locking script, and the input data can be either in an
unlocking script or hard coded in the same locking script.
[sign]:= OP_HASH256 𝑘 −1 OP_MUL 𝑘 −1 𝑟𝑎 OP_ADD 𝑛 OP_MOD 𝑟 [toDER]
SIGHASH_FLAG OP_CAT

Input data: 𝑚
Remarks
1. The equation for computing 𝑠 in the ECDSA signature is 𝑘 −1 (𝑧 + 𝑟𝑎) 𝑚𝑜𝑑 𝑛, where 𝑧 is
the double SHA256 of the message 𝑚 to be signed. We write the equation in script as
(𝑘 −1 𝑧 + 𝑘 −1 𝑟𝑎) 𝑚𝑜𝑑 𝑛 to indicate that 𝑘 −1 and 𝑘 −1 𝑟𝑎 can be precomputed. It would be
very costly to compute modular inverse 𝑘 −1 𝑚𝑜𝑑 𝑛 in script. As we are not using the
signature for authenticity, the private key 𝑎 and the ephemeral key 𝑘 can be chosen at
wish and shown publicly.
2. The script segment [sign] as part of the locking script needs to fix both the
ephemeral key 𝑘 and the private key 𝑎. Although anyone can generate a valid signature
using [sign], the focus is on the input 𝑚. The requirement is that there is only one
value of 𝑚 that can pass OP_CHECKSIG for any given spending transaction. If the
private key or the public key is not fixed, then the transaction will be malleable. The
detail can be found in Section 2. If the ephemeral key 𝑘 is not fixed, then anyone can

WP1605

© nChain Licensing AG

4 of 25

PUSHTX and Its Building Blocks

use a different 𝑘 to create a valid transaction with a different transaction ID, which is
not desirable in some use cases.
3. To further optimise the script segment, one can choose small values for 𝑘 and 𝑎 such
as 1, and they can be the same every time. Note that if 𝑘 = 𝑎 = 1, then 𝑠 = 𝑧 +
𝐺𝑥 𝑚𝑜𝑑 𝑛, where 𝐺𝑥 is the 𝑥-coordinate of the generator point 𝐺. The compressed
public key will be 𝐺𝑥 too. The definition of [sign] can be re-written as
[sign]:= OP_HASH256 𝐺𝑥 OP_ADD 𝑛 OP_MOD 𝐺𝑥 [toDER]
SIGHASH_FLAG OP_CAT
4. The script segment [toDER] is to convert the pair (𝑟, 𝑠) to the canonical DER format.
This is the only format accepted by OP_CHECKSIG. It forces 𝑠 to be in the range
between 0 and 𝑛/2 to avoid transaction ID malleability. Although this is a policy rule in
the Bitcoin network, it seems that Bitcoin nodes are unlikely to accept alternatives.
5. Note that SIGHASH_FLAG in [sign] is compulsory as OP_CHECKSIG expects it. It can
be used to specify which part of the spending transaction should be pushed to the
stack. For example, the flag ALL would require all the inputs and outputs to be
included in the message 𝑚, while SINGLE|ANYONECANPAY would require the input
corresponding to this locking script and its paired output to be included in 𝑚.
6. If we extend the script segment to “OP_DUP [sign] < 𝑃𝐾 >” with input 𝑚, the stack
from bottom to top will look like [𝑚, 𝑆𝑖𝑔, 𝑃𝐾] after its execution. A call to
OP_CHECKSIGVERIFY will consume the signature and the public key, leaving 𝑚 on the
top of the stack. If the verification is successful, then one can be convinced that the
message 𝑚 left on the stack is an accurate representation of the spending transaction.

1.2 Constructing the message in-script
The signed message in its serialised format is different from the serialised transaction. The
latter gives away all the information about the transaction, while the signed message
unintentionally conceals some information about the transaction in hash values and offers
some information about the output being spent, i.e., its value and its locking script.
The message 𝑚 cannot be fully embedded in the locking script as it contains the locking script
itself and some unknown information on the future spending transaction. Only some of the
fields can be explicitly enforced in the locking script, e.g., version, sequence number, or
locktime. The message 𝑚 is either provided in the unlocking script in its entirety or constructed
in script with some inputs from the unlocking script and instructions from the locking script. We
will focus on the latter as it is more restrictive from the perspective of a spending transaction.
Note that the goal of constructing the message is to enforce desired values for some data fields
in the spending transaction. The table below captures all the data fields in the message and
whether they should or can be fixed in the locking script. “Optional” is given if it is use-case
specific.

WP1605

© nChain Licensing AG

5 of 25

PUSHTX and Its Building Blocks

Table 1 - Components of a signed message
Items

Fixed explicitly in locking script or not

1

Version 4 bytes little endian

Optional

2

Hash of input outpoints 32 bytes

Infeasible due to circular reference of TxID

3

Hash of input sequence numbers 32
bytes

Optional, recommend “Not” to allow more
flexibility in spending transaction

4

Input outpoint 32 bytes + 4 bytes in little
endian

Infeasible due to circular reference of TxID
(although 4 bytes index can be optional)

5

Length of previous locking script

Optional, recommend “Not” for simplicity

6

Previous locking script

Infeasible due to circular reference of the
locking script

7

Value of previous locking script 8 bytes
(little endian)

Optional

8

Sequence number 4 bytes (little endian)

Optional

9

Hash of outputs 32 bytes

Optional if it is known before hand,
otherwise, infeasible to be fixed.

10

Locktime 4 bytes in little endian

Optional

11

Sighash flag 4 bytes in little endian

Recommend being fixed for more
restrictiveness

From now on, the data fields in the table will be referred as item 1, 2, 3, etc.
When it is optional, whether to provide the data in the locking or unlocking script depends on
use cases. A general rule is that if the data is available or known at the time of creating the
locking script, then they can be included in the locking script. Another aspect to consider is the
size of the transaction and its spending transaction. By shifting the data between the locking
and unlocking script, one can shift some of the transaction fee cost between the senders of the
two transactions.
Note that when we say infeasible due to circular references, the granularity is set at date fields.
For example, partial locking script or even a small part of a transaction ID (e.g., fixing the first
two bytes of a 32-byte transaction ID and allow iterations through some fields in a serialised
transaction) can be fixed in the locking script if required.
As mentioned earlier, although the focus is to construct the message 𝑚, the goal is to use 𝑚 to
enforce values on different fields in the spending transaction. To enforce the data behind the
hash values, i.e., item 9, the locking script should be designed to request the pre-image, hash
WP1605

© nChain Licensing AG

6 of 25

PUSHTX and Its Building Blocks

them in-script, and then construct the message to be signed in-script. Taking item 9 as an
example, to enforce the outputs in the current transaction, we can have
[outputsRequest]:= OP_DUP OP_HASH256 OP_ROT OP_SWAP OP_CAT <item 10 and
11> OP_CAT
Input data: <item 1 to 8> <serialised outputs in current transaction>
Remarks
1. The script segment [outputsRequest] takes item 1 to 8 and the serialised outputs
on the stack to construct item 9, and concatenate with item 10 and 11 to obtain the
message 𝑚 in-script. By calling [sign] <𝐺𝑥 > OP_CHECKSIGVERIFY after
[outputsRequest] and passing the verification, one can be convinced that the
serialised outputs left on the top of the stack is a true representation of the outputs in
the current transaction.
2. It is also very useful to leave a copy of <item 1 to 7> on the stack for comparison.
This can be achieved by modifying the script segment as below.
[outputsRequest]:= OP_2DUP OP_HASH256 OP_SWAP <item 8> OP_CAT
OP_SWAP OP_CAT <item 10 and 11> OP_CAT

Input data: <item 1 to 7> <serialised outputs in current
transaction>
After executing the modified [outputsRequest] on the input data, we can call
[sign] <𝐺𝑥 > OP_CHECKSIGVERIFY to consume the message. The stack will have the
current serialised outputs on the top followed by <item 1 to 7>. We will use the
modified script segment later to enforce the output in a spending transaction.
3. It is simpler if consecutive items are grouped together as in <item 1 to 7>. They are
either all in an unlocking script or all fixed in a locking script. However, a more granular
approach is available at a potential cost of having a more complex script.
Note that the serialisation format for current outputs is
a. value of the output 8 bytes (little endian),
b. length of the locking script,
c. the locking script, and
d. concatenate serialised outputs in order if there is more than one output.
The serialisation format for previous output (item 5 to 7) in a signed message is
a. length of the locking script,
b. the locking script, and
c. value of the output 8 bytes (little endian).
In the following example, we will compare the previous output with the output in the current
spending transaction and force them to be identical. The two formats will be useful for
designing the locking script for the comparison.

WP1605

© nChain Licensing AG

7 of 25

PUSHTX and Its Building Blocks

1.3 Example of a PELS
Suppose that Alice is a root Certificate Authority (CA) and Bob is a subordinate CA. Alice is going
to delegate some work to Bob which would require Bob to publish transactions on-chain as
attestations to certificates. Alice does not want Bob to spend the output on anything else.
Therefore, Alice is going to force all the subsequent spending transactions to have a fixed
[P2PKH Bob] locking script and a fixed output value. Bob can spend the output as he can
generate valid signatures, but he cannot choose any output other than sending the same
amount to himself. For illustration purpose and simplicity, we ignore OP_RETURN payload
throughout the example.
Alice constructs the initial transaction as shown below.

𝑇𝑥𝐼𝐷0
Version

1

Locktime

0

In-count

1

Out-count

1

Input list

Output list

Outpoint

Unlocking script

nSeq

Value

Locking script

𝑂𝑢𝑡𝑝𝑜𝑖𝑛𝑡𝐴

< 𝑆𝑖𝑔𝐴 >
< 𝑃𝐾𝐴 >

FFFFFFFF

1000

[outputsRequest][sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP
OP_HASH160 <𝐻(𝑃𝐾𝐵 )> OP_EQUALVERIFY OP_CHECKSIG

Figure 1 - Initial transaction that contains a PELS output
The script segments are defined as:
[outputsRequest]:= OP_2DUP OP_HASH256 OP_SWAP <item 8> OP_CAT OP_SWAP
OP_CAT <item 10 and 11> OP_CAT
[sign]:= OP_HASH256 𝐺𝑥 OP_ADD 𝑛 OP_MOD [toDER] SIGHASH_FLAG OP_CAT
𝐺𝑐𝑜𝑚𝑝𝑟𝑒𝑠𝑠𝑒𝑑
[toDER]:= [toCanonical][concatenations]
[toCanonical]1:= OP_DUP 𝑛/2 OP_GREATERTHAN OP_IF 𝑛 OP_SWAP OP_SUB OP_ENDIF
[concatenations]:= OP_SIZE OP_DUP <0x24> OP_ADD <0x30> OP_SWAP OP_CAT
<0220||𝐺𝑥 ||02> OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
Note that “OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP OP_CAT
OP_EQUALVERIFY” is to extract the previous output from the signed message (verified and left
on the top of the stack), then swap the position of the value field and the locking script to form
the expected current output, and finally compare it with the actual current output provided in
the unlocking script and its integrity is implied by the integrity of the signed message.
The length of the locking script is roughly

1

This is to make sure that 𝑠 is in the range between 0 and 𝑛/2. If 𝑠 > 𝑛/2, we let 𝑠 = 𝑛 − 𝑠.

WP1605

© nChain Licensing AG

8 of 25

PUSHTX and Its Building Blocks

(7 + 12) + (6 + 32 + 32 + 33) + (6 + 32 + 32) + (11) + (15 + 34) + (14 + 20)
= 286 = 0𝑥011𝑒.
Note that these numbers are not meant to be precise, but they should be accurate enough to
be in the right magnitude. For a more accurate result, please refer to Appendix.
To spend the transaction, Bob creates the spending transaction as below.

𝑇𝑥𝐼𝐷1
Version

1

Locktime

0

In-count

1

Out-count

1

Input list
Outpoint

Unlocking script

𝑇𝑥𝐼𝐷0 ||0

< 𝑆𝑖𝑔𝐵 >
< 𝑃𝐾𝐵 >
< 𝐷𝑎𝑡𝑎1 >
< 𝐷𝑎𝑡𝑎2 >

Output list
nSeq

FFFFFFFF

Value

Locking script

1000

[outputsRequest][sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP
OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG

Figure 2 - spending the PELS output
The unlocking script contains a data element 𝐷𝑎𝑡𝑎1 which represents items 1 to 7 and can be
written as:
010000002268f59280bdb73a24aae224a0b30c1f60b8a386813d63214f86b98261a6b8763
bb13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e70665044𝑇𝑥𝐼𝐷0 00000
000011e{[outputsRequest] [sign] OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT
OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP
OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG}e803000000000000
Table 2 - Data element 𝑑𝑎𝑡𝑎1 explained
Items

Value

1

version

01000000

2

Hash of input outpoints

2268f59280bdb73a24aae224a0b30c1f60b8a3868
13d63214f86b98261a6b876

3

Hash of input sequence
numbers

3bb13029ce7b1f559ef5e747fcac439f1455a2ec7
c5f09b72290795e70665044

4

Input outpoint

𝑇𝑥𝐼𝐷000000000

5

Length of previous locking script

011e

WP1605

© nChain Licensing AG

9 of 25

PUSHTX and Its Building Blocks

6

Previous locking script

{[outputsRequest] [sign]
OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT
OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP
OP_CAT OP_EQUALVERIFY OP_DUP OP_HASH160
<H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG}

7

Value of previous locking script

e803000000000000

The data element 𝐷𝑎𝑡𝑎2 represents the output in 𝑇𝑥𝐼𝐷1 (value || locking script length || locking
script) and can be written as:
e803000000000000011e{[outputsRequest] [sign] OP_CHECKSIGVERIFY OP_SWAP
<0x68> OP_SPLIT OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP OP_CAT
OP_EQUALVERIFY OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG}
The full script to be executed during the validation of 𝑇𝑥𝐼𝐷1 is
< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 > [outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP OP_CAT
OP_EQUALVERIFY OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG
After the first OP_CHECKSIGVERIFY, we will have < 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 > on
the stack (rightmost on the top).
Table 3 - Stack execution
Step

The stack

To execute

1

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 >

OP_SWAP <0x68>

2

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎2 > < 𝐷𝑎𝑡𝑎1 > <0x68>

OP_SPLIT OP_NIP

3

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎2 >
<011e
{[outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY
OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG}
e803000000000000>

OP_SWAP OP_8 OP_SPLIT

4

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎2 >
<011e
{[outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY

OP_SWAP OP_CAT

WP1605

© nChain Licensing AG

10 of 25

PUSHTX and Its Building Blocks

OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG}
e803000000000000>
<e803000000000000>
<011e
{[outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY
OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG}>
5

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎2 >
<011e
{[outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY
OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG}
e803000000000000>
<011e
{[outputsRequest] [sign] OP_CHECKSIGVERIFY
OP_SWAP <0x68> OP_SPLIT OP_NIP OP_SWAP OP_8
OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY
OP_DUP OP_HASH160 <H(PK_B)> OP_EQUALVERIFY
OP_CHECKSIG}
e803000000000000>

OP_EQUALVERIFY

6

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 >

OP_DUP OP_HASH160
<H(PK_B)>
OP_EQUALVERIFY
OP_CHECKSIG

7

True

The size of 𝑇𝑥𝐼𝐷1 is
𝑣𝑒𝑟𝑠𝑖𝑜𝑛 + 𝑙𝑜𝑐𝑘𝑡𝑖𝑚𝑒 + 𝑖𝑛𝑝𝑢𝑡 + 𝑜𝑢𝑡𝑝𝑢𝑡
= 4 + 4 + (36 + 72 + 33 + 104 + 287 + 8 + 287 + 8 + 4) + (8 + 287)
= 1142 bytes.
Transaction Fee
Given the current setting, Bob can add his own input to cover the transaction fee. If Alice uses
SIGHASH_SINGLE|ANYONECANPAY in the script segment [sign], then Bob can add another
output to collect changes. This effectively makes the enforcement from Alice’s locking script
perpetual. One can think of this as a node-enforced smart contract between Alice and Bob.
It is also possible for the locking script to take the transaction fee into consideration. After step
3, the top element on the stack is the value from the previous output. By adding <𝑇𝑥𝐹𝑒𝑒>
OP_SUB before the concatenation in step 4, Alice allows Bob to pay the transaction fee from the
previous output. This will lead to diminishing value of the output over spends, which can act as
a desired feature as it sets the total number of spends Bob are entitled to.

WP1605

© nChain Licensing AG

11 of 25

PUSHTX and Its Building Blocks

1.4 Optimisation
As 𝐷𝑎𝑡𝑎1 contains 𝐷𝑎𝑡𝑎2 , we can construct 𝐷𝑎𝑡𝑎2 from 𝐷𝑎𝑡𝑎1 . In other words, we assume that
the current output is identical to the previous output and use the previous output to construct
the message. If it passes OP_CHECKSIG, then the two outputs must be identical. The script
segment of [outputsRequest] can be re-written as:
[outputsRequest]:= OP_2DUP OP_CAT OP_TOALTSTACK OP_SWAP OP_CAT OP_HASH256
<item 8> OP_SWAP OP_CAT OP_FROMALTSTACK OP_SWAP OP_CAT OP_CAT <item 10
and 11> OP_CAT
Input data: <item 1 to 4> <item 5 and 6> <item 7>
With this new [outputsRequest], we can update the locking script in 𝑇𝑥𝐼𝐷0 and 𝑇𝑥𝐼𝐷1 as:
[outputsRequest][sign] OP_CHECKSIGVERIFY OP_DUP OP_HASH160 <H(PK_B)>
OP_EQUALVERIFY OP_CHECKSIG
and the unlocking script as:
< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 > < 𝐷𝑎𝑡𝑎3 >
where 𝐷𝑎𝑡𝑎1 is item 1 to 4:
010000002268f59280bdb73a24aae224a0b30c1f60b8a386813d63214f86b98261a6b8763bb
13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e70665044𝑇𝑥𝐼𝐷000000000
𝐷𝑎𝑡𝑎2 is item 5 and 6:
011b{[outputsRequest] [sign] OP_CHECKSIGVERIFY OP_SWAP <0x68> OP_SPLIT
OP_NIP OP_SWAP OP_8 OP_SPLIT OP_SWAP OP_CAT OP_EQUALVERIFY OP_DUP
OP_HASH160 <H(PK_B)> OP_EQUALVERIFY OP_CHECKSIG}
𝐷𝑎𝑡𝑎3 is item 7: e803000000000000.
The size of 𝑇𝑥𝐼𝐷1 is 941 bytes. A step-by-step execution is given below, where Step 1 to 5 is
from [outputsRequest].
Table 4 - Stack execution with optimisation
Step

The stacks

To execute

1

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 > < 𝐷𝑎𝑡𝑎3 >

OP_2DUP OP_CAT
OP_TOALTSTACK

WP1605

© nChain Licensing AG

12 of 25

PUSHTX and Its Building Blocks

2

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > < 𝐷𝑎𝑡𝑎2 > < 𝐷𝑎𝑡𝑎3 >
ALTSTACK: <item 5 to 7>

OP_SWAP OP_CAT
OP_HASH256

3

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > <item 9>
ALTSTACK: <item 5 to 7>

<item 8> OP_SWAP
OP_CAT

4

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > <item 8 and 9>
ALTSTACK: <item 5 to 7>

OP_FROMALTSTACK
OP_SWAP OP_CAT

5

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > < 𝐷𝑎𝑡𝑎1 > <item 5 to 9>

OP_CAT <item 10 and
11> OP_CAT

6

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 > <item 1 to 11>

[sign]
OP_CHECKSIGVERIFY

7

< 𝑆𝑖𝑔𝐵 > < 𝑃𝐾𝐵 >

OP_DUP OP_HASH160
<H(PK_B)>
OP_EQUALVERIFY
OP_CHECKSIG

8

True

Further improvement can be made by using the alt stack for storing 𝐺𝑥 and 𝑛. Each of them is
𝑛

of size 32 bytes. As 𝐺𝑐𝑜𝑚𝑝𝑟𝑒𝑠𝑠 is 𝐺𝑥 and 2 can be derived from 𝑛, we can use several opcodes to
reference them from the alt stack. However, it would introduce complications when designing
the script. For example, a comparison of two versions of [sign] is shown below.
Before:
[sign]:= OP_HASH256 𝐺𝑥 OP_ADD 𝑛 OP_MOD [toDER] SIGHASH_FLAG OP_CAT 𝐺𝑥
[toDER]:= [toCanonical][concatenations]
[toCanonical]:= OP_DUP 𝑛/2 OP_GREATERTHAN OP_IF 𝑛 OP_SWAP OP_SUB OP_ENDIF
[concatenations]:= OP_SIZE OP_DUP <0x24> OP_ADD <0x30> OP_SWAP OP_CAT
<0220||G_x> OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT

WP1605

© nChain Licensing AG

13 of 25

PUSHTX and Its Building Blocks

After:
[sign]:= OP_HASH256 𝐺𝑥 OP_DUP OP_TOALTSTACK OP_ADD 𝑛 OP_DUP OP_TOALTSTACK
OP_MOD [toDER] SIGHASH_FLAG OP_CAT OP_FROMALTSTACK
[toDER]:= [toCanonical][concatenations]
[toCanonical]:= OP_DUP OP_FROMALTSTACK OP_DUP OP_TOALTSTACK OP_2 OP_DIV
OP_GREATERTHAN OP_IF OP_FROMALTSTACK OP_SWAP OP_SUB OP_ENDIF
[concatenations]:= OP_SIZE OP_DUP <0x24> OP_ADD <0x30> OP_SWAP OP_CAT
<0220> OP_FROMALTSTACK OP_DUP OP_TOALTSTACK OP_CAT OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT
We added 15 opcodes and removed two instances of 𝐺𝑥 and two instances of 𝑛. The total saving
is (32 × 2 + 32 × 2) − 15 = 113 bytes. Therefore, the size of the spending transaction 𝑇𝑥𝐼𝐷1 can
be further reduced to 828 bytes.
It is safe to say that with all available optimisations, the size of a spending transaction can be
around 1KB.
Note that any example scripts shown above are not meant to be used in mainnet transactions.
They are written for illustration purpose. Some simplifications are implicitly assumed. For
example, reversing endianness is omitted. For a more practical and comprehensive guide,
please refer to Appendix.

WP1605

© nChain Licensing AG

14 of 25

PUSHTX and Its Building Blocks

2

Security Analysis

In this section, we offer some security proofs and analysis around PUSHTX. This is considered a
formal approach to PUSHTX and some of the insights we described in the previous section.
First of all, we notice that there are effectively two signatures in the script execution. One is
created by PUSHTX technique, the other one is provided in the unlocking script for P2PKH. The
first signature provides data integrity and enables enforcement on the spending transaction,
while the second provides authenticity and ensure that only the intended recipient can create
the spending transaction2.

Claim 1:

If (𝑟, 𝑠) is a valid ECDSA signature with respect to a public key 𝑃 on the messages 𝑚,
then it is computationally infeasible to construct 𝑚 ′ such that 𝑚 ′ ≠ 𝑚 and (𝑟, 𝑠) is
still valid on 𝑚 ′ with respect to 𝑃, assuming that the cryptographic hash function
used is pre-image resistant and collision resistant.

Proof:
let 𝑧 = ℎ𝑎𝑠ℎ(𝑚) and 𝑧 ′ = ℎ𝑎𝑠ℎ(𝑚 ′) for some 𝑚 ′.
Let 𝑢 = 𝑧𝑠 −1 𝑚𝑜𝑑 𝑛 , 𝑢′ = 𝑧 ′ 𝑠 −1 𝑚𝑜𝑑 𝑛, 𝑣 = 𝑟𝑠 −1 𝑚𝑜𝑑 𝑛, and 𝑅 = 𝑘𝐺 where
𝑅𝑥 = 𝑟 𝑚𝑜𝑑 𝑛.
Also let 𝑅′ denote the points such that 𝑅′ ≠ 𝑅 and 𝑅𝑥′ = 𝑟 𝑚𝑜𝑑 𝑛.
Note that3 𝑅′ can either be −𝑅 or one of the two points, (𝑥, ±𝑦),
where 𝑥 = 𝑅𝑥 + 𝑛 if 𝑅𝑥 < 𝑛 and 𝑥 = 𝑅𝑥 − 𝑛 if 𝑅𝑥 > 𝑛.
So, from the signature verification, we have [𝑢𝐺 + 𝑣𝑃]𝑥 = [𝑢′ 𝐺 + 𝑣𝑃]𝑥 = 𝑟 𝑚𝑜𝑑 𝑛.
There are two cases to consider.
Case 1: 𝑢𝐺 + 𝑣𝑃 = 𝑢′ 𝐺 + 𝑣𝑃 = 𝑅
 𝑢 = 𝑢′ 𝑚𝑜𝑑 𝑛
 𝑧 = 𝑧 ′ 𝑚𝑜𝑑 𝑛
 𝑚 = 𝑚 ′ under the assumption that the hash function is collision
resistant.
Case 2: 𝑢𝐺 + 𝑣𝑃 = 𝑅 and 𝑢′ 𝐺 + 𝑣𝑃 = 𝑅′
 𝑢′ 𝐺 = 𝑅′ − 𝑣𝑃
 Given that the message 𝑚, the public 𝑃, and the value 𝑟 are all fixed,
there are maximum three different values that 𝑢′ can take, each of which
corresponds to a value of 𝑅′.

In some use cases where authenticity is not required and it is desired to have anyone
being able to create a spending transaction, the script segment P2PKH can be omitted.
However, any implications and risks should be analysed and assessed before such
approach.
3
On secp256k1 curve, the group order 𝑛 is less than the curve modulo 𝑝, but they are of
the same bit length. Therefore, an equation 𝑥 = 𝑎 𝑚𝑜𝑑 𝑛 will have maximum two solutions
for 𝑥 ∈ [0, 𝑝 − 1]. The maximum number of solutions can only be achieved when 𝑎 ∈ [0, 𝑝 −
𝑛).
2

WP1605

© nChain Licensing AG

15 of 25

PUSHTX and Its Building Blocks

 𝑧 ′ = 𝑢′ 𝑠 also has maximum three values.
 Finding 𝑚 ′ such that ℎ𝑎𝑠ℎ(𝑚 ′ ) = 𝑧 ′ where 𝑧 ′ can only be one of the three
fixed values is computationally infeasible assuming that the hash
function is pre-image resistant.
Therefore, we can conclude that it is computationally infeasible to find 𝑚 ′ such that
𝑚 ′ ≠ 𝑚 and (𝑟, 𝑠) is still valid on 𝑚 ′ with respect to 𝑃.
Note that Claim 1 implies that PUSHTX technic is secure to use if we assume that double
SHA256 is preimage resistant and collision resistant. Moreover, it implies that the data integrity
is preserved even when we sacrifice authenticity in ECDSA by making both the private key and
the ephemeral key available to the public.

Claim 2:

Public key 𝑃 must be fixed in the locking script.

Reasoning:
Suppose 𝑃 is not fixed and (𝑟, 𝑠) is a valid signature with respect to 𝑃 on 𝑚.
Let 𝑧 ′ = ℎ𝑎𝑠ℎ(𝑚 ′ ). 𝑢′ = 𝑧 ′ 𝑠 −1 , and 𝑣 = 𝑟𝑠 −1
We want to find 𝑃′ such that 𝑢′ 𝐺 + 𝑣𝑃 ′ = 𝑅
𝑃 ′ = 𝑣 −1 (𝑅 − 𝑢′ 𝐺)
Now (𝑟, 𝑠) is valid with respect to 𝑃 ′ on 𝑚′.
Therefore 𝑃 must be fixed in the locking script.

Claim 3:

𝑘 should be fixed in the locking script.

Reasoning:
Suppose (𝑟, 𝑠) is a valid signature generated in the locking script with respect to 𝑃
on 𝑚.
Suppose 𝑘 is not fixed in the locking script and is provided in the unlocking script.
Then an adversary can:
1.

intercept the spending transaction, and

2.

replace 𝑘 with 𝑘′ in the unlocking script.

Then (𝑟 ′ , 𝑠 ′ ) generated in the locking script will be a valid signature with respect to
𝑃 on 𝑚.
Transaction will still be valid, but the transaction ID is changed.

Claim 4:

Sighash flag should be fixed in the locking script.

Reasoning:
Suppose (𝑟, 𝑠) is a valid signature generated in the locking script with respect to 𝑃
on 𝑚.
Suppose sighash flag is not fixed in the locking script and is provided in the
unlocking script.
1.

WP1605

Intercept the spending transaction

© nChain Licensing AG

16 of 25

PUSHTX and Its Building Blocks

2.

Change the sighash flag

3.

Update the message 𝑚 accordingly to 𝑚 ′.

In some use case, this would invalidate the transaction. E.g., the locking script
expects multiple inputs and outputs with sighash flag “ALL”; changing the flag to
anything else would invalidate the script execution.
In others, this would change the transaction ID without invalidating the transaction.
E.g., the locking script only enforces conditions on the outputs of its spending
transaction; adding or removing “ANYONECANPAY” would not invalidate the
transaction, but will change the transaction ID.

WP1605

© nChain Licensing AG

17 of 25

PUSHTX and Its Building Blocks

3

Appendix

All implementations have been tested on regtest on Bitcoin SV v1.0.8. Please be warned that the
scripts below are for testing purpose only. Any attempt of using them on mainnet should
undergo thorough testing and rigorous reviews.
The result shows that a spending transaction is of size 1415 bytes. The overhead is mainly
coming from reversing endianness. A 32-byte string would require 124 bytes of opcodes to
reverse its endianness. We need to reverse endianness twice in the locking script. The locking
script appears both in the unlocking script and the output in the spending transaction.
Therefore, the total overhead from endianness in our implementation is over 500 bytes. We did
not use Alt Stack to store 𝐺𝑥 and 𝑛 in our current implementation for simplicity. This would save
us about 200 bytes in total.
We present two example locking scripts first and explain what they do. We then present two
transactions with one spending the other using the second locking script, demonstrating that
the locking script works and can be spent as expected.
Locking Script 1 (LS1) – generateSig and checkSig
"aa517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b0
2070b87ce9562a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafeff
ffffffffffffffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafefff
fffffffffffffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafe
ffffffffffffffffffffffffffffff007c946882766b6b517f517f517f517f517f517f517
f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f
517f517f517f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbba
c55a06295ce870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279
be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ac"
Input: serialised transaction message for signing as in Section 1.2
The locking script takes the message 𝑚, and
1. double SHA256 on 𝑚 to obtain 𝑧,
2. reverse endianness of 𝑧,
3. add 0x00 to ensure 𝑧 is not interpreted as a negative number,
4. call OP_BIN2NUM to have minimal encoding on 𝑧 (would take care the case when step
3 introduces redundancy),
5. compute 𝑠 = 𝑧 + 𝐺𝑥 𝑚𝑜𝑑 𝑛,
6. convert 𝑠 to 𝑛 − 𝑠 if 𝑠 > 𝑛/2,
7. obtain length of 𝑠,
8. reverse endianness of 𝑠 (32 bytes),
9. reverse one more byte if the length of 𝑠 is greater than 32,
10. compute the total length of a DER signature (0x24 + 𝑙𝑒𝑛𝑔𝑡ℎ 𝑜𝑓 𝑠),
11. add DER prefix 0x30,
12. concatenate 𝑟 = 𝐺𝑥 ,
WP1605

© nChain Licensing AG

18 of 25

PUSHTX and Its Building Blocks

13. concatenate 𝑠,
14. concatenate sighash flag “ALL”,
15. push compressed public key 𝐺𝑥 , and
16. call OP_CHECKSIG.
Note that in step 7 to 9, we have assumed that the length of 𝑠 is either 32 or 33 bytes. However,
𝑠 may be shorter than that. Some care should be taken to pad 𝑠 using OP_NUM2BIN if it is too
short.
Locking Script 2 (LS2) – constructMsg + LS1 + P2PKH
"6e810200029458807c7eaa04ffffffff7c7e7e7e7e0800000000410000007eaa517f517f
517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b02070b87ce95
62a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafefffffffffffff
fffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffff
ffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafefffffffffff
fffffffffffffffffff007c946882766b6b517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517
f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbbac55a06295ce
870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279be667ef9dcb
bac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a914751e76e8199196
d454941c45d1b3a323f1433bd688ac"
Input: <𝑆𝑖𝑔> <𝑃𝐾> <Item 1 to 4> <Item 5 and 6> <Item 7>
The locking script takes a pair of signature and public key, and item 1 to 7 as in the table in
Section 1.2 in three PUSHDATA operations, and
1.

take the previous value and work out the new output value (subtracting a fixed
transaction fee),
2. take the previous locking script as the new locking script for the new output,
3. concatenate the new output value and new locking script to obtain the new output,
4. double SHA256 the new output to obtain the hash of outputs (item 9),
5. push sequence number (item 8),
6. concatenate to get message string (item 1 to 9),
7. push locktime and sigahash flag (item 10 and 11),
8. concatenate to obtain the message to be signed 𝑚,
9. call LS1 with OP_CHECKSIGVERIFY, and
10. call P2PKH to check 𝑆𝑖𝑔 with respect to 𝑃𝐾.
Transaction 0 – genesis transaction
{
"txid":
"88b9d41101a4c064b283f80ca73837d96f974bc3fbe931b35db7bca8370cca34",
"hash":
"88b9d41101a4c064b283f80ca73837d96f974bc3fbe931b35db7bca8370cca34",
"version": 1,
"size": 730,
"locktime": 0,

WP1605

© nChain Licensing AG

19 of 25

PUSHTX and Its Building Blocks

"vin": [
{
"txid":
"52685bdbaae5c76887c23cee699bc48f293192a313c19b9fad4c77b993655df5",
"vout": 0,
"scriptSig": {
"asm":
"3044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
02201229c3605c61c4133b282cc30ece9e7d5c3693bf2cd1c03a3caadcd9f25900a5[ALL|
FORKID]
0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
"hex":
"473044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f817
9802201229c3605c61c4133b282cc30ece9e7d5c3693bf2cd1c03a3caadcd9f25900a5412
10279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
},
"sequence": 4294967295
}
],
"vout": [
{
"value": 49.99999388,
"n": 0,
"scriptPubKey": {
"asm": "OP_2DUP OP_BIN2NUM 512 OP_SUB 8 OP_NUM2BIN OP_SWAP OP_CAT
OP_HASH256 -2147483647 OP_SWAP OP_CAT OP_CAT OP_CAT OP_CAT
0000000041000000 OP_CAT OP_HASH256 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT 0 OP_CAT OP_BIN2NUM
9817f8165b81f259d928ce2ddbfc9b02070b87ce9562a055acbbdcf97e66be79 OP_ADD
414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00 OP_MOD
OP_DUP 414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00
2 OP_DIV OP_GREATERTHAN OP_IF
414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00
OP_SWAP OP_SUB OP_ENDIF OP_SIZE OP_DUP OP_TOALTSTACK OP_TOALTSTACK 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT OP_FROMALTSTACK 32 OP_GREATERTHAN OP_IF 1 OP_SPLIT OP_ENDIF

WP1605

© nChain Licensing AG

20 of 25

PUSHTX and Its Building Blocks

OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_FROMALTSTACK 32 OP_GREATERTHAN OP_IF OP_SWAP OP_CAT OP_ENDIF OP_SIZE
OP_DUP 36 OP_ADD 48 OP_SWAP OP_CAT
022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179802
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT 65 OP_CAT
0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
OP_CHECKSIGVERIFY OP_DUP OP_HASH160
751e76e8199196d454941c45d1b3a323f1433bd6 OP_EQUALVERIFY OP_CHECKSIG",
"hex":
"6e810200029458807c7eaa04ffffffff7c7e7e7e7e0800000000410000007eaa517f517f
517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b02070b87ce95
62a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafefffffffffffff
fffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffff
ffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafefffffffffff
fffffffffffffffffff007c946882766b6b517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517
f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbbac55a06295ce
870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279be667ef9dcb
bac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a914751e76e8199196
d454941c45d1b3a323f1433bd688ac",
"type": "nonstandard"
}
}
],
"hex":
"0100000001f55d6593b9774cad9f9bc113a39231298fc49b69ee3cc28768c7e5aadb5b68
52000000006a473044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f
2815b16f8179802201229c3605c61c4133b282cc30ece9e7d5c3693bf2cd1c03a3caadcd9
f25900a541210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f
81798ffffffff019cef052a01000000fd32026e810200029458807c7eaa04ffffffff7c7e
7e7e7e0800000000410000007eaa517f517f517f517f517f517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f51
7f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e01007e81209817f8
165b81f259d928ce2ddbfc9b02070b87ce9562a055acbbdcf97e66be799321414136d08c5
ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00977621414136d08c5e
d2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff005296a06321414136d08
c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff007c946882766b6b51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517
f517f517f517f517f517f517f517f517f517f517f517f517f6c0120a063517f687c7e7c7e

WP1605

© nChain Licensing AG

21 of 25

PUSHTX and Its Building Blocks

7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e6c0120a0637c7e6882760124930130
7c7e23022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179
8027e7c7e7c7e01417e210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959
f2815b16f81798ad76a914751e76e8199196d454941c45d1b3a323f1433bd688ac0000000
0"
}
Transaction 1 – spending transaction
{
"txid":
"c700e1d6c995e4c77014536d4431be84d7fb40d3fbef52ed85be2ad06414eac8",
"hash":
"c700e1d6c995e4c77014536d4431be84d7fb40d3fbef52ed85be2ad06414eac8",
"version": 1,
"size": 1415,
"locktime": 0,
"vin": [
{
"txid":
"88b9d41101a4c064b283f80ca73837d96f974bc3fbe931b35db7bca8370cca34",
"vout": 0,
"scriptSig": {
"asm":
"3044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
0220388bd5f619c02287145cf0bb3bc440f883b09e35e67a4adcf50635800219ed34[ALL|
FORKID]
0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
01000000fb472de1f838d9560dc7b19b1ab62b0c6ed60580779017d3cd32d22bcc051ce13
bb13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e7066504434ca0c37a8
bcb75db331e9fbc34b976fd93738a70cf883b264c0a40111d4b98800000000
fd32026e810200029458807c7eaa04ffffffff7c7e7e7e7e0800000000410000007eaa517
f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f
517f517f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b02070b8
7ce9562a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafeffffffff
ffffffffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafefffffffff
fffffffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafeffffff
ffffffffffffffffffffffff007c946882766b6b517f517f517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbbac55a06
295ce870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279be667e
f9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a914751e76e81
99196d454941c45d1b3a323f1433bd688ac 9cef052a01000000",
"hex":
"473044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f817
980220388bd5f619c02287145cf0bb3bc440f883b09e35e67a4adcf50635800219ed34412
10279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f817984c6801
WP1605

© nChain Licensing AG

22 of 25

PUSHTX and Its Building Blocks

000000fb472de1f838d9560dc7b19b1ab62b0c6ed60580779017d3cd32d22bcc051ce13bb
13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e7066504434ca0c37a8bc
b75db331e9fbc34b976fd93738a70cf883b264c0a40111d4b988000000004d3502fd32026
e810200029458807c7eaa04ffffffff7c7e7e7e7e0800000000410000007eaa517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517
f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b02070b87ce9562
a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafefffffffffffffff
fffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffff
ffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafefffffffffffff
fffffffffffffffff007c946882766b6b517f517f517f517f517f517f517f517f517f517f
517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f5
17f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbbac55a06295ce87
0b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279be667ef9dcbba
c55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a914751e76e8199196d4
54941c45d1b3a323f1433bd688ac089cef052a01000000"
},
"sequence": 4294967295
}
],
"vout": [
{
"value": 49.99998876,
"n": 0,
"scriptPubKey": {
"asm": "OP_2DUP OP_BIN2NUM 512 OP_SUB 8 OP_NUM2BIN OP_SWAP OP_CAT
OP_HASH256 -2147483647 OP_SWAP OP_CAT OP_CAT OP_CAT OP_CAT
0000000041000000 OP_CAT OP_HASH256 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT 0 OP_CAT OP_BIN2NUM
9817f8165b81f259d928ce2ddbfc9b02070b87ce9562a055acbbdcf97e66be79 OP_ADD
414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00 OP_MOD
OP_DUP 414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00
2 OP_DIV OP_GREATERTHAN OP_IF
414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00
OP_SWAP OP_SUB OP_ENDIF OP_SIZE OP_DUP OP_TOALTSTACK OP_TOALTSTACK 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1

WP1605

© nChain Licensing AG

23 of 25

PUSHTX and Its Building Blocks

OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1 OP_SPLIT 1
OP_SPLIT OP_FROMALTSTACK 32 OP_GREATERTHAN OP_IF 1 OP_SPLIT OP_ENDIF
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_FROMALTSTACK 32 OP_GREATERTHAN OP_IF OP_SWAP OP_CAT OP_ENDIF OP_SIZE
OP_DUP 36 OP_ADD 48 OP_SWAP OP_CAT
022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179802
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT 65 OP_CAT
0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
OP_CHECKSIGVERIFY OP_DUP OP_HASH160
751e76e8199196d454941c45d1b3a323f1433bd6 OP_EQUALVERIFY OP_CHECKSIG",
"hex":
"6e810200029458807c7eaa04ffffffff7c7e7e7e7e0800000000410000007eaa517f517f
517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9b02070b87ce95
62a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafefffffffffffff
fffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffff
ffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaebafefffffffffff
fffffffffffffffffff007c946882766b6b517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517
f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcbbac55a06295ce
870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e210279be667ef9dcb
bac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a914751e76e8199196
d454941c45d1b3a323f1433bd688ac",
"type": "nonstandard"
}
}
],
"hex":
"010000000134ca0c37a8bcb75db331e9fbc34b976fd93738a70cf883b264c0a40111d4b9
8800000000fd1503473044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d
959f2815b16f817980220388bd5f619c02287145cf0bb3bc440f883b09e35e67a4adcf506
35800219ed3441210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815
b16f817984c6801000000fb472de1f838d9560dc7b19b1ab62b0c6ed60580779017d3cd32
d22bcc051ce13bb13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e70665
04434ca0c37a8bcb75db331e9fbc34b976fd93738a70cf883b264c0a40111d4b988000000
004d3502fd32026e810200029458807c7eaa04ffffffff7c7e7e7e7e08000000004100000
07eaa517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f
517f517f517f517f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c

WP1605

© nChain Licensing AG

24 of 25

PUSHTX and Its Building Blocks

7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2ddbfc9
b02070b87ce9562a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dcaebafe
ffffffffffffffffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dcaebafef
fffffffffffffffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6dcaeba
feffffffffffffffffffffffffffffff007c946882766b6b517f517f517f517f517f517f5
17f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667ef9dcb
bac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e01417e2102
79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad76a9147
51e76e8199196d454941c45d1b3a323f1433bd688ac089cef052a01000000ffffffff019c
ed052a01000000fd32026e810200029458807c7eaa04ffffffff7c7e7e7e7e08000000004
10000007eaa517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f51
7f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f7c7e7c7e7c7
e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e
7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e01007e81209817f8165b81f259d928ce2
ddbfc9b02070b87ce9562a055acbbdcf97e66be799321414136d08c5ed2bf3ba048afe6dc
aebafeffffffffffffffffffffffffffffff00977621414136d08c5ed2bf3ba048afe6dca
ebafeffffffffffffffffffffffffffffff005296a06321414136d08c5ed2bf3ba048afe6
dcaebafeffffffffffffffffffffffffffffff007c946882766b6b517f517f517f517f517
f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f517f
517f517f517f517f517f517f517f517f6c0120a063517f687c7e7c7e7c7e7c7e7c7e7c7e7
c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c7e7c
7e7c7e7c7e7c7e7c7e7c7e7c7e6c0120a0637c7e68827601249301307c7e23022079be667
ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798027e7c7e7c7e0141
7e210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798ad7
6a914751e76e8199196d454941c45d1b3a323f1433bd688ac00000000"
}

WP1605

© nChain Licensing AG

25 of 25

