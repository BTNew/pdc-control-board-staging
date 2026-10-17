-- Craig approved the exact Department 138 review on 17 October 2026.
-- Private normalized description hashes avoid publishing operational source text.
-- This migration does not import emails, change hours, move bookings or reopen work.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR NOT pdc_codex_intake_private.management_connection()
 OR coalesce(auth.uid()::text,'')<>''
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure))
 IS DISTINCT FROM '7c4ffedf2eb35877daf24359ef31d46b'
 THEN RAISE EXCEPTION 'reviewed_category_projection_changed'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
LOCK TABLE public.workshop_bookings IN SHARE MODE;
LOCK TABLE public.pdc_pilbara_service_operations,public.vehicle_workshop_line_adjustments IN SHARE ROW EXCLUSIVE MODE;

-- BEGIN RULE STORAGE
CREATE TABLE pdc_work_categories_private.import_rules_20261017(
 description_hash text PRIMARY KEY CHECK(length(description_hash)=32),
 category text CHECK(category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET'))
);
ALTER TABLE pdc_work_categories_private.import_rules_20261017 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.import_rules_20261017 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO pdc_work_categories_private.import_rules_20261017(description_hash,category) VALUES
('0178eb5c8535a15c2bbc41b1afd29d0e','SUBLET'),
('033af6ed9959c733a71b6890da9a87c1','BUS_MECHANICAL'),
('03c6379d43e223ea5b5d1534ef6150ca','BUS_ACCESSORIES'),
('03fda957b06fad6139fd38a62a8031e7','SUBLET'),
('051dbd9896a90d94827c7ec994e57080','SUBLET'),
('0542ba8d033916d4d124cb03b981d50d','BUS_MECHANICAL'),
('059fcef0da860d8a67fad5577a51e057','BUS_QA'),
('0608493461239b1a532369fd3b310cce','BUS_ACCESSORIES'),
('067451385eecbfc49a2a69db1dcae824','BUS_QA'),
('069cd274bc942973966df75485974a75','BUS_ELECTRICAL'),
('069d52525caa6aff49eec0eda9949d2b','BUS_MECHANICAL'),
('093aab3bf07a4384ef8452e4aa9d9234','BUS_MECHANICAL'),
('09c966f2787eb1568ff0f9d95984cf91','BUS_ELECTRICAL'),
('0c00112d13a091c9136e086aeef32fef','BUS_QA'),
('0c8033ac5272fa1dd51b24bc29de9589','BUS_MECHANICAL'),
('0eb91579e98fa037f58aa01b4388451d','BUS_ELECTRICAL'),
('0ed3d1dfd84b7d794a8f30f5a7cf4a92','BUS_MECHANICAL'),
('0f4fad978a709f97262a1e2e6a11f7c8','BUS_ELECTRICAL'),
('105e8720c8ed64d0143faff63aac260f','BUS_ACCESSORIES'),
('117ed39ea90d4d2c71eb54a8fbc9ca54','SUBLET'),
('12ec79805b3b17b0f9c051fa4f98ea56','BUS_ELECTRICAL'),
('163f0b752ac2112e111702fb527b301a','BUS_MECHANICAL'),
('1664d38b01fd9a7d1f8b3dc89b9dea8e','BUS_ELECTRICAL'),
('172bf22e4d1100b09df5175104678c61','BUS_ACCESSORIES'),
('17ddd81be663c44386a7acb21f2e6036','BUS_ELECTRICAL'),
('18177b61c9437f9d8d2bad29e1a10fff',NULL),
('198edbfc129ee773f4a3953d465ae853','SUBLET'),
('19c6227c32e380e357369d4d11f9199f','SUBLET'),
('1a2b554f529941dee1b59439d234dc90','SUBLET'),
('1bfeff836582175f0e136161251383d9','BUS_ELECTRICAL'),
('1c6dc6dc2456a1744ae22ae383024aa8','BUS_MECHANICAL'),
('1d98d36ec8aa3841ab617ec0b2237c8a','BUS_ELECTRICAL'),
('1e26d14e0cf1dc6824747bd98d1a7eb4',NULL),
('1ecf13912aa631f93702fc1cd2bf8a75','BUS_ACCESSORIES'),
('1eded6fb659376604b6762bc32de86c6','BUS_MECHANICAL'),
('1f5c97142d665962d1706bedb4eee5fd','BUS_ELECTRICAL'),
('1f77dfa82686a0a8fe6f13fa86d2b0d3','BUS_ELECTRICAL'),
('1fa9cfba3df5c8b6b07b197ed3e8c92f','BUS_ACCESSORIES'),
('1ffe6b351ba8d7bbb5aa9377a3e004b7','SUBLET'),
('20ab7017c7278368d42781306947fb7f','BUS_MECHANICAL'),
('20cd054c1715c3e9fc7c19b42f0ebcc1','SUBLET'),
('224fab1b3edce4de484747b4b7c6ec70','BUS_QA'),
('230f16680805714eba8c897a9694a442','BUS_MECHANICAL'),
('244599029910227a727d05d5e1a3931e','BUS_QA'),
('253e2d9b75c4c2fd1675149ba9a289e8','BUS_QA'),
('264e0b44778e1234f71ae43c90d56e35','BUS_MECHANICAL'),
('269bb2045180f150e9442632a0ccbf4b','BUS_MECHANICAL'),
('282217406ac5c816d99bfaf071d94ed8','BUS_ELECTRICAL'),
('28df792ac55eb0207b6534f3ae6af6ad','BUS_ELECTRICAL'),
('29ec426bf27fab1d9c407be0275451bf','BUS_QA'),
('29fe1d4eb0e3951fdc7baca1ad0beb51','BUS_ELECTRICAL'),
('2a014ccbdf66eb947c6c68663c81e082','BUS_ELECTRICAL'),
('2a8f95cb4cc2e3dfd0ef71d43c891137',NULL),
('2af76ca7f025998f781e5836af9a154b','SUBLET'),
('2d577f0116601823209ce817f9628a18',NULL),
('2d839ebda2933c931820c152a8e36720','BUS_QA'),
('2dbae2edc689842ddda090efa5c63c5e','BUS_ELECTRICAL'),
('2e5033e10a2812810ce41d9b8eac249f','BUS_ELECTRICAL'),
('2f4efcc0e149e90124ff8558806c5a56','BUS_MECHANICAL'),
('30b21b721379cf5d91d31af3a21e677d','TINT'),
('3111e7907f0965d4efd8be146f740577','BUS_PIT'),
('31146b3e398961345aaa9c61e6da574d','BUS_MECHANICAL'),
('31fb383f22b3863a9ec134bd26cec30d','SUBLET'),
('32cdd75203ae7390d943e3ecada8c5db','BUS_MECHANICAL'),
('334cdd2eed66e8f63528e66b9dd5a362','BUS_MECHANICAL'),
('34b8db5e8db72d24928f77d472df7472','SUBLET'),
('34e18ee8cf07b23cef109e7c74231a25','TINT'),
('34f864c0c2b69791d45689a09202f5d3','BUS_QA'),
('34f9b2a0ccf5f99ba2e0d590bb73bf94','BUS_ELECTRICAL'),
('359d7090f3753afb8f32987469a3f5df',NULL),
('35d29cae8945f6e7312aa11ebb51ba6f','BUS_ELECTRICAL'),
('37da6b3ff4508654475ff6e5b88b7a81','BUS_MECHANICAL'),
('37da9bc400dddfb648d2eff0d7be257d','BUS_ELECTRICAL'),
('383bad9920f4f3c0c9ea478521a483c2','BUS_MECHANICAL'),
('386d41b896704dd31c04f0c6d089e7c0','BUS_ACCESSORIES'),
('387eabb1dc2cd38a316b95de41e0786e',NULL),
('3886fe7f3c739cb2f56ff1f1125545d2','TINT'),
('38d51eaec4af3f8fb526bbb7f33452ea','TYRE'),
('3974cd85181a80fe3bc49120b564ee4a','BUS_MECHANICAL'),
('3bfc4a977e2502754ff65a148faaf6dd','BUS_ELECTRICAL'),
('3c2e39a4c99c86c00b0e35c5d60ad3f1','BUS_QA'),
('3cf81302679cbf81eafb768e9932df9b','BUS_QA'),
('3d2b26cceca13406a6478957f7f9dde0','BUS_PIT'),
('3dafe12e28afc80b915a4d475faf3cd9','BUS_ELECTRICAL'),
('3df68b8d96372d655b17fd9c51bf5101','BUS_QA'),
('3e1d966a2f0d51963008fa1d916f1c40','SUBLET'),
('3f400cf0f737bd4319d228435ff415e2','BUS_MECHANICAL'),
('403f31a44a9db4d67d4c01ee1186863a','BUS_MECHANICAL'),
('418b47241f836880b401a36fe178f196','BUS_QA'),
('422ac089d46c80a2dc9429fc60430a2a','BUS_ACCESSORIES'),
('43bc022974d3cc89f5313380aab21b42','TYRE'),
('43c7d7c93ab25836c24f37f3cb26fbe8','BUS_ELECTRICAL'),
('4588416694494aa30e9424cd87fdf4f8','BUS_ELECTRICAL'),
('47835b9c2165ba37b1558fcedef52c4d','SUBLET'),
('47c93a24e6c9100e980001e21e20c2c1','BUS_ELECTRICAL'),
('48417455617ec20eea6672d8926989d2','BUS_MECHANICAL'),
('48eb94aa79c9880dc112e5d00b940cfb','BUS_ELECTRICAL'),
('4ab764f8c6be8bcdcabdde898ca530a9',NULL),
('4c3d4eb09781297c3b87709468dd4b15','BUS_ACCESSORIES'),
('4c57715cffef12f445f5c6c61a4bfbf4','TINT'),
('4d6bb20520fadd279b01da431575f1be','BUS_MECHANICAL'),
('4dcae6b02cbad853e3c066d9ddbf5ebe','BUS_ELECTRICAL'),
('4e09f4daecea80f793cc4225c5c49d4f','BUS_QA'),
('4e60879c1414489207891a7f2bb61e68','BUS_QA'),
('4eeb6694ff164d177b1fe512afb9c000','BUS_MECHANICAL'),
('50a5295c2b24c832013ede0ea7ef4b79','SUBLET'),
('52b783ea211fbcb6d16a3a0c41dae57e','BUS_ELECTRICAL'),
('5396b4eaa3eb7327b5d457a47e342c60','BUS_ELECTRICAL'),
('545c2dd16a06d12e4a4af842680a965b','BUS_ELECTRICAL'),
('54662c8cbdcf2cff907eac06f3b17f68','BUS_ELECTRICAL'),
('564b266b567312cdef41af92e197db60',NULL),
('565ed05c4099d1111394588f3fd1026b','BUS_ACCESSORIES'),
('57f55af900ec648939a0e801c34b2cdd','BUS_ACCESSORIES'),
('58a43c32dbde48fc306fe1a9546f4c43','BUS_MECHANICAL'),
('5a2f8193f98e2c366bfd749400f96052',NULL),
('5a92dc4429a172ad3025c89ea300ad2b',NULL),
('5b99d15fa496204c3aeca8ac6362de98','BUS_ELECTRICAL'),
('5bbbdf599fb0f1e8213a1f82a70e96bd','BUS_MECHANICAL'),
('5cd8e47a6f958aab08be52e7bdd141bc','BUS_QA'),
('5eab536fd75f4b84c0dab59c27d56f9f','BUS_MECHANICAL'),
('61488d0bbf11301ddba6aa6acc7599c3','TYRE'),
('62df8c81bf1769cf5c5ff04323f12e13','BUS_ACCESSORIES'),
('632c9526ff11d60527185d2754d9d839','BUS_MECHANICAL'),
('63d6008950dde07a9f6ad455c4f0bd10','SUBLET'),
('63d7aeb181e13ad025e21c8bfe706d06','BUS_QA'),
('6524d9802586978bebb035bad6bc50e8','BUS_ELECTRICAL'),
('65abc1545c5163fcff2db6889643bf2e','BUS_ELECTRICAL'),
('669fe57a3a828b6cf833ca2f71ba12e8','BUS_MECHANICAL'),
('69b986b966255fd17816e559a3b48fa2','BUS_MECHANICAL'),
('6ab9b624dea0c465190b06cef2e9a24d','BUS_QA'),
('6b2a2949f5719e1a9c27a1a4ad192a1e','BUS_MECHANICAL'),
('6b6dee55c6e351275c8b6282b93e8db3','BUS_MECHANICAL'),
('6cd4f3031a3fc0fbf4d0fb21f4e04e40','BUS_ELECTRICAL'),
('6d8f3efc4c4bdd562359bc3cb1b55be3','BUS_MECHANICAL'),
('6e5e92d4fb90c35af1d449171f267f5e','TINT'),
('6fa1b6eeec1e5f56877620ae0831d98d','BUS_ELECTRICAL'),
('6fb60f62a9ebe8ea029c8f31cfdff6e9','BUS_MECHANICAL'),
('6fd9561fb8b26eaab875f91aefdd6501','BUS_ACCESSORIES'),
('70e8ae08155f4ed12c780b0f511f350d','BUS_MECHANICAL'),
('71393c768b4f624c1d70e740d665852a','BUS_ELECTRICAL'),
('728e839cc0816f13e0d46605c7048f2d',NULL),
('72f212f419c06a6bbea88c1981bba4c4','BUS_QA'),
('749667fcb8598959dc263550b9a0e80f','BUS_MECHANICAL'),
('7641dbcdf6b0d6b9521f73b6d007950e','BUS_ACCESSORIES'),
('765389f6f6963db68a4aa52bb6b5d38b','BUS_QA'),
('76d918d3da2098bb9d69f8ae19416521','BUS_MECHANICAL'),
('76ff38bb49feb2794f2b58a5a35c8a9d','BUS_MECHANICAL'),
('7753404e62d31b632e9d77cc6bb6485a','BUS_ELECTRICAL'),
('78caba123538071da7f5246be4efb00f','BUS_MECHANICAL'),
('79c40d3059d5e5fb63ee538999452186','BUS_ELECTRICAL'),
('79eb92cc12c225dbe81f6a3a629521ac','BUS_QA'),
('79eff49ea36a06fcce228aa2619b4769','BUS_ELECTRICAL'),
('7d0b1204e3c8333d86abf85be41e9000','BUS_ELECTRICAL'),
('7e1be096b83f28a4b648b1a54910dcbe','BUS_ELECTRICAL'),
('7ec506c58dee238a12fcd4539c815c3a','BUS_ELECTRICAL'),
('80fde6c1607fc922f87f35038ac14d61','BUS_ELECTRICAL'),
('8193cb9e24f750d7527c406124b8654e','BUS_ELECTRICAL'),
('81f5c161fa606d64873fde9604733b4c','BUS_QA'),
('81f7ea5916b0b4ccd54a4c6e7cb3410d','SUBLET'),
('826defd9fb9201c8b1573e8aecd53ea5','BUS_ELECTRICAL'),
('832ca37a5c41f9817841811a6e3b1d88','BUS_QA'),
('84cfc6b4ad9c67aff79a6a4924986bb1','BUS_ELECTRICAL'),
('84d9fa99ffdbeadd3383ad20d7d01da7','BUS_ELECTRICAL'),
('854227e432820d9b09f566d23b06d066','BUS_ELECTRICAL'),
('8565151075ebe28c1874b5470d3654bb','BUS_MECHANICAL'),
('860ec7970206c38a1ed8058f6de2cf84','BUS_ELECTRICAL'),
('862cb8d06bd74185258c25dfa689e16a','SUBLET'),
('898b74d4355ed719f1c40cbd199983de','SUBLET'),
('89be83f4edc4d6b4209145ab842f2679','BUS_MECHANICAL'),
('8a23d898cc0f15b1e5082504d3104c5b','SUBLET'),
('8b035199a48d4deaf8dc4d526fbb5ef4','BUS_ELECTRICAL'),
('8e677444de2316e598359fb1c1709a24','BUS_MECHANICAL'),
('8e8e4aaa752676369435bb99913c5656','BUS_ELECTRICAL'),
('8f0c465554e624f7afa4e1545268bb79',NULL),
('8f75ce8429561f4b244a540a6a6b2427','BUS_QA'),
('903ba7100859b51505a02b74a517fb95','BUS_MECHANICAL'),
('907336400fa127acb988255ac7e8bd37','BUS_MECHANICAL'),
('920732673dcfd7b68255d9ef3d0ef412',NULL),
('924137ef50711a8848f4c8e6b828d636','TYRE'),
('9269f18aabb825ac064ccfffb36bcfd3','BUS_MECHANICAL'),
('941e073f1d9d0483a5444bf51a5857d9','BUS_ELECTRICAL'),
('9557a008a9cd6cf23d5d0bbd5762091a','BUS_ELECTRICAL'),
('95772df158d6091146537ddbd04ce395','BUS_MECHANICAL'),
('9589ef6a2a199ae5c5bff46145545e12','BUS_MECHANICAL'),
('95a2d3b29112b11584eb099027a4f896','BUS_ELECTRICAL'),
('97fd03896eb98579ae76f86da7888add','BUS_ELECTRICAL'),
('984fd81a660a4f96eedf26154ea54143','SUBLET'),
('98a0e84fe59dd3d10fe4b7b105a1944b','BUS_ELECTRICAL'),
('9dc56973c83154f1dc362c7a9d41d06a','BUS_ELECTRICAL'),
('9e8a6e9d298a21bf3a1150757ec08d9f','SUBLET'),
('9e90ae62bbc8dc8f2717278e906c48ef','TYRE'),
('a106ecf043d8d513f98ecdc578f1e4ed','BUS_ACCESSORIES'),
('a10e2be9b8367c38bc44dec35b53e50c','TYRE'),
('a1476e4290e043b38e496979f7bf31c4','BUS_ELECTRICAL'),
('a377fa4667ff4d3cb209dd7fb5001b6f','BUS_ELECTRICAL'),
('a4415714ae897e57832eadd85abd06cc','BUS_MECHANICAL'),
('a452d1200c698eebada4154f7075c150','SUBLET'),
('a4e848f54d88429d8c3e177663ff4710','TYRE'),
('a5853f4025a738f5b01697d03f8a8948','SUBLET'),
('a7ae4a9cc51c4f7e09a2682a29ca97bb','BUS_MECHANICAL'),
('a8483d91f7295c0d7b733484482fe74f','BUS_ELECTRICAL'),
('a9dc3a30f6a119ab7719117fe13e6f88','BUS_ELECTRICAL'),
('ac80769117206b4386f9fc7ffe8fbe9e','BUS_MECHANICAL'),
('ac9913d50a77244d763775b245b6ddb9','BUS_MECHANICAL'),
('aee6d0e0d9f4c3640043a6d3744ec101','BUS_ELECTRICAL'),
('af58d0d11697abdf1f8b88b36ba31352','BUS_ELECTRICAL'),
('b1e5b3967084bc94fd9d8ba74846c17f','BUS_MECHANICAL'),
('b2744fcb6dc876840f53e3130abc7982','BUS_ELECTRICAL'),
('b31ac6db6d7a24ad8477cde59636c25d','BUS_MECHANICAL'),
('b371c8f9fb7f03398c9db63538537f2c','BUS_ELECTRICAL'),
('b4f92171aee65fbe070ed950c1f341c5','BUS_QA'),
('b52c7cdc13263acead95540e706380b0','BUS_ELECTRICAL'),
('b55e0798c4203262c50f0070b9406f03','BUS_MECHANICAL'),
('b581ff57736b8f95848fcd4dc8535c13','TYRE'),
('b6958b65d77707cfbfc0dd3f10b812b7','BUS_MECHANICAL'),
('b6aec26f7e261083df70442d6657d5fd','BUS_MECHANICAL'),
('b6ed92d1901e877c1946b69800e41550','BUS_QA'),
('b816922225135c977a6aba76cb8ddc5c','BUS_MECHANICAL'),
('b8a557b4be57fd43842f5d171a7c8b64',NULL),
('b903b6fb3b0bb6703e87478d7356fb0a','BUS_MECHANICAL'),
('b9ef0edd27dea8b0bccc22195a325736','BUS_QA'),
('bae677484eed54c4eef6be5451a1ed57','BUS_MECHANICAL'),
('bb6e5c23a7abf2f2065e5e5d53d65976','BUS_ELECTRICAL'),
('bc313be6f23e13e1149acf67e5e0b714','BUS_MECHANICAL'),
('bc619de7aef15e3a64fccf034cc420f5','BUS_ACCESSORIES'),
('bd1fdf920a3f3c0d7ca86311aaa11deb','BUS_ELECTRICAL'),
('bd30e3bf0064ab2130b79daf279d419b','BUS_MECHANICAL'),
('bd634dc8e154db0737c7410a34bd32bc','BUS_MECHANICAL'),
('be1a3e1676ef40d79e25e2d85996393f','SUBLET'),
('bed0935fa1858aa187a44cffb51080f0','BUS_MECHANICAL'),
('bfc5743e2706e836da60dbe7a8219f0f','BUS_QA'),
('c0c1541a760eed0f6e8a86a30a1a5216','BUS_MECHANICAL'),
('c1bab22cf5fb7fdf7d721d55982bd06e','BUS_MECHANICAL'),
('c1e40434ff33c69cb707a12443d22e87','BUS_ELECTRICAL'),
('c210009a9fec69c227fda781e00e9074','BUS_ELECTRICAL'),
('c3c600ed341f6d94609ddd1726868835','BUS_ACCESSORIES'),
('c3d135f1c95f3b189ca3ca5c9a96ed8c','BUS_ELECTRICAL'),
('c448ad0ea90c3c45a173c7f736cafd43','BUS_MECHANICAL'),
('c56203461e2faad0cd92a3c9b009972b','BUS_MECHANICAL'),
('c925c545114725a8b37f2a67030b1c1b','BUS_MECHANICAL'),
('cac0b0b0fc8715768fc8eb22a2dac14a','BUS_MECHANICAL'),
('cbbdd6077b056b5f213a85329f6e0ab6','BUS_MECHANICAL'),
('cc99ede9c881d978d8ee8119d23fd8bf','BUS_ELECTRICAL'),
('cd1af7fed33faf17a82b68dbb05bb507','BUS_ELECTRICAL'),
('cd8e89f471b9b21a738b6f2707a164db','BUS_ACCESSORIES'),
('cdf4fc15a17fca19197da96519af51a6','SUBLET'),
('ce62365d4c6237a976529784eb1bae24','BUS_MECHANICAL'),
('cfe1fe6eff87cf71071100f1b500600e','BUS_MECHANICAL'),
('d02483f2c3bd6caeb68c7965f23d226d','BUS_QA'),
('d088eb0c816f9f9221e47a070e5da488','SUBLET'),
('d0f445b3443ca5cc888f27ad1c9dcde0','SUBLET'),
('d243b0304699fee1919e22c3699b6324','TINT'),
('d2d15d74f7f973106f8a454d2fe30056','BUS_ELECTRICAL'),
('d3d5aaf31cf924aecd0dd1be97e2698f','BUS_ELECTRICAL'),
('d4c3f7ca27ee2005fb3b69ddd5e56ee7','BUS_QA'),
('d5e7dfb4f5d4d97133a1e463057fab35','BUS_ELECTRICAL'),
('d684b95e9e6ea29c97f3bb97d4f67794','BUS_QA'),
('d68d370c0f1ae9dd92986b5a139f2d16','BUS_ELECTRICAL'),
('da1718a8d548ca6b422caad71b120f65',NULL),
('da37a67eef730d94656e3ef76a3dc6c5','SUBLET'),
('db7216b9d636fecf6a1d063b07b4202e','BUS_MECHANICAL'),
('dd0f0d8939b9e1dfee0137eade6457c1','BUS_MECHANICAL'),
('dd4fc835126127a5688ac8f10dc1f974','BUS_ELECTRICAL'),
('e009a67b9a5b64a7fb5e84393890e94a','BUS_MECHANICAL'),
('e1df3b3b27ce7159ffe85950cc84b8ad','BUS_ELECTRICAL'),
('e21992ae4f3fe22591f70ef8abd3a61e',NULL),
('e2674854521e5666c986d38c95acdec7','BUS_MECHANICAL'),
('e2af7ecc82b898b257b1c46545d1b15b','BUS_QA'),
('e399b65ae2baff80ce9ed2d12dc2b28f','BUS_ELECTRICAL'),
('e3f3cdb83655d4a525610f5888b0dcb8','BUS_MECHANICAL'),
('e52b375f22ef310a863730a9e4b15184','SUBLET'),
('e64bfc6d3e313735d176406a7e745c24','BUS_ELECTRICAL'),
('e662be1a63e954fa10149392e4f96530','BUS_QA'),
('e6ed03371e3b5494c165d16fe7a1066b','TINT'),
('e8d7502eb1f16c4f238cf61791a9a5f3','BUS_MECHANICAL'),
('e96a141296681f7462f03e46ffcf2f73','SUBLET'),
('e9deeb852a3ab176746666c1cfc51199','BUS_ACCESSORIES'),
('ea1b8c57a98fb3e602a237eaae04d210','BUS_MECHANICAL'),
('ea329b1509d600eb7938ae1565f753d7','BUS_QA'),
('ec0b5fd3e17de992e07586c7fec13ac7','BUS_QA'),
('ed891f01e98672e5cde4fb883eafe4bf','SUBLET'),
('edb6c375297d793ae40cf97b00013777','BUS_ELECTRICAL'),
('ede456cf0d45b3dbe9a7b28933970a6b','BUS_ELECTRICAL'),
('ee6b6eea64bfcdca0b87f63a62908f0f','BUS_MECHANICAL'),
('ee9b17a1ac50d3797cae3e78a95e27f4','BUS_PIT'),
('eeb61a56cde94dda619fb3013adce742','SUBLET'),
('eef16205f972c3e6ed8157dbe7eb6af8','BUS_MECHANICAL'),
('f27e1082bad77ae28edd9606b04cf402','BUS_ELECTRICAL'),
('f2ca9dcfd8e46f1aee2497caceee5745','BUS_MECHANICAL'),
('f3823a1f4b43143d1550d4954bf883f2','BUS_QA'),
('f5086939e4ecb190a34120a496ce54d1','BUS_QA'),
('f51278065a3077f07ebdb5d91ed38805','BUS_MECHANICAL'),
('f51bb0e9b71e36947d8f2b77ad295a1a','BUS_QA'),
('f72a8fdf4c96963ea7f59b860281cf6b','BUS_MECHANICAL'),
('f78b9ed20749794a65541e71a07c86bf','SUBLET'),
('f83d0094d2514aac2236e130c24f48ac','BUS_MECHANICAL'),
('f8ca97ea5e011b71aaee62e125487cf2','BUS_ACCESSORIES'),
('faaa174632a63bb686e2c7e9e9449a89','SUBLET'),
('ffec9f07ce09d46943d72dd992630151','BUS_MECHANICAL')
;
CREATE TABLE pdc_work_categories_private.import_baseline_20261017(
 vehicle_id uuid NOT NULL,
 line_identity text NOT NULL,
 source_signature text NOT NULL,
 PRIMARY KEY(vehicle_id,line_identity)
);
ALTER TABLE pdc_work_categories_private.import_baseline_20261017 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.import_baseline_20261017 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_work_categories_private.import_description_hash_20261017(description text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
 SELECT md5(upper(regexp_replace(btrim(coalesce(description,'')),'\s+',' ','g')))
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.import_description_hash_20261017(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb,preserve boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
DECLARE category text; hours numeric;
BEGIN
 IF preserve IS TRUE OR line->>'department' IS DISTINCT FROM '138'
 OR NOT coalesce((line->>'active')::boolean,true)
 OR coalesce((line->>'completed')::boolean,false)
 OR coalesce((line->>'rejected')::boolean,false)
 THEN RETURN line; END IF;
 SELECT r.category INTO category FROM pdc_work_categories_private.import_rules_20261017 r
 WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(line->>'description');
 -- NULL is either an explicitly held package or an unmatched description.
 category:=coalesce(category,'UNALLOCATED_MAPPING_REVIEW');
 hours:=CASE WHEN jsonb_typeof(line->'estimated_hours')='number' THEN (line->>'estimated_hours')::numeric END;
 -- Do not turn nominal import estimates into internal bay reservations.
 IF category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','TINT','TYRE')
 AND (hours IS NULL OR hours<=0.01)
 AND NOT(category='BUS_QA' AND hours=0 AND coalesce((line->>'zero_hour_task')::boolean,false))
 THEN category:='UNALLOCATED_MAPPING_REVIEW'; END IF;
 RETURN line||jsonb_build_object('work_category',category,
  'stage_code',pdc_work_categories_private.stage(category),
  'zero_hour_task',category='BUS_QA' AND hours=0);
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.route_import_line_20261017(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
-- END RULE STORAGE

-- Preserve all existing source identities, including completed and archived history.
CREATE TEMP TABLE import_split_before_20261017 ON COMMIT DROP AS
SELECT v.vehicle_id,public.pdc_qc_operation_lines_379(v.vehicle_id) lines
FROM (SELECT DISTINCT vehicle_id FROM public.pdc_pilbara_service_operations WHERE btrim(department)='138' AND vehicle_id IS NOT NULL) v;
INSERT INTO pdc_work_categories_private.import_baseline_20261017
SELECT v.vehicle_id,l->>'line_identity',pdc_work_categories_private.source_signature(l)
FROM import_split_before_20261017 v
CROSS JOIN LATERAL jsonb_array_elements(v.lines) l
WHERE l->>'department'='138';

-- Copy the reviewed body without moving the public function's identity/ACL.
DO $copy$ DECLARE definition text;
BEGIN
 definition:=pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure);
 definition:=replace(definition,'public.pdc_qc_operation_lines_379(',
  'pdc_work_categories_private.before_import_rules_20261017(');
 EXECUTE definition;
END $copy$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.before_import_rules_20261017(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- BEGIN CANONICAL PROJECTION
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH source AS MATERIALIZED(
  SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id)) WITH ORDINALITY x(l,ord)
 ), routed AS(
 SELECT ord,pdc_work_categories_private.route_import_line_20261017(l,
  h.source_signature=pdc_work_categories_private.source_signature(l)
  OR coalesce((l->>'category_version')::integer,0)>0
  OR coalesce(a.manual_assignment_locked,false)
  OR EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews r
   WHERE r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
   AND r.source_signature=pdc_work_categories_private.source_signature(l))
  OR EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=p_vehicle_id AND w.completed AND s.code=l->>'stage_code')
  OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
    AND ((b.work_category IS NOT NULL AND b.work_category_scope ? (l->>'line_identity'))
     OR (b.work_category IS NULL AND s.code=l->>'stage_code')))
 ) l
 FROM source
 LEFT JOIN pdc_work_categories_private.import_baseline_20261017 h ON h.vehicle_id=p_vehicle_id AND h.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 ) SELECT coalesce(jsonb_agg(l ORDER BY ord),'[]'::jsonb) FROM routed
$fn$;
-- END CANONICAL PROJECTION
DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM import_split_before_20261017 b
  WHERE b.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379(b.vehicle_id))
 THEN RAISE EXCEPTION 'existing_source_hours_categories_or_history_changed'; END IF;
END $verify$;
-- Required-work recalculation already consumes the canonical projection on import.
-- No current source line or required/completed flag is rewritten by this release.
