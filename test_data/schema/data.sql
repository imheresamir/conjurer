--
-- PostgreSQL database dump
--

-- Dumped from database version 10.15 (Debian 10.15-1.pgdg90+1)
-- Dumped by pg_dump version 10.15 (Debian 10.15-1.pgdg90+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (role_id, created_at, policy_id) FROM stdin;
!:!:root	2021-04-03 01:34:38.52174	\N
myConjurAccount:user:admin	2021-04-03 01:34:38.555847	\N
\.


--
-- Data for Name: resources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resources (resource_id, owner_id, created_at, policy_id) FROM stdin;
!:webservice:accounts	!:!:root	2021-04-03 01:34:38.541824	\N
\.


--
-- Data for Name: annotations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.annotations (resource_id, name, value, policy_id) FROM stdin;
\.


--
-- Data for Name: authenticator_configs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authenticator_configs (id, resource_id, enabled) FROM stdin;
\.


--
-- Data for Name: credentials; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.credentials (role_id, client_id, api_key, encrypted_hash, expiration, restricted_to) FROM stdin;
myConjurAccount:user:admin	\N	\\x479dae77ec3b3b3cf5ac5a424faafbb71c66ad85e110158ad841218fbe638aa38f9c6b5213343c88712f774304fca34b9af5e3ed3181b4d3b763b0088a4d237d2aeefa3a6dcdd0ff35ad2938ee19c5406e6cf9	\N	\N	{}
\.


--
-- Data for Name: host_factory_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.host_factory_tokens (token_sha256, token, resource_id, cidr, expiration) FROM stdin;
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.permissions (privilege, resource_id, role_id, policy_id) FROM stdin;
\.


--
-- Data for Name: policy_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.policy_versions (resource_id, role_id, version, created_at, policy_text, policy_sha256, finished_at, client_ip) FROM stdin;
\.


--
-- Data for Name: policy_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.policy_log (policy_id, version, operation, kind, subject, at) FROM stdin;
\.


--
-- Data for Name: resources_textsearch; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resources_textsearch (resource_id, textsearch) FROM stdin;
!:webservice:accounts	'account':1A 'webservic':2C
\.


--
-- Data for Name: role_memberships; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_memberships (role_id, member_id, admin_option, ownership, policy_id) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_migrations (filename) FROM stdin;
20121215032820_create_keystore.rb
20160628212347_create_roles.rb
20160628212349_create_resources.rb
20160628212358_create_role_memberships.rb
20160628212428_create_permissions.rb
20160628212433_create_annotations.rb
20160628222441_create_credentials.rb
20160630172059_create_secrets.rb
20160705141848_create_authz_functions.rb
20160801210433_create_id_functions.rb
20160815131453_create_policy_version.rb
20160815131521_add_policy_column.rb
20160906135444_create_owner_functions.rb
20170404125612_create_host_factories.rb
20170710163523_create_resources_textsearch.rb
20180410071554_current_policy.rb
20180410092453_policy_log.rb
20180422043957_resource_visibility.rb
20180508164825_add_expiration.rb
20180530162704_is_role_ancestor_of.rb
20180618161021_role_graph.rb
20180705192211_credentials_restricted_to_cidr.rb
20190307154241_change_permissions_primary_key.rb
20191112025200_create_authenticator_config.rb
20200605203735_add_policy_version_client_ip.rb
20200811181056_reset_fingerprint_column.rb
20201119122834_update_annotation_update_textsearch.rb
201808131137612_policy_log_trigger_bypass.rb
\.


--
-- Data for Name: secrets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.secrets (resource_id, version, value, expires_at) FROM stdin;
\.


--
-- Data for Name: slosilo_keystore; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.slosilo_keystore (id, key, fingerprint) FROM stdin;
authn:!	\\x472719566e4012a8acd1fac04e936ddcdedb123b3280007590aade3227b6dab1f45720c396126895c98df5ae5d9b96b6422f731b37655ff97b602926b05567e4e4ea549d73c9dc1607fcc6fe51459d4838e2eca46ab0029cb9fcc564c2f270c5a8683c4fc4c7a5d58f4f51ec26252090ddfdb57328f8444ea000e527d0053353a14dccea4fe1001a000bbc5054bf7b3994f4466b3e881007ffca073c0d01a02fe2060d02b3adc86814fb2debd86b273b52b2935caf13e0f6d859aad1952d01929c878986e09f9fe2807f2ce5ebbc80a9a1c7e8b991c090dc3b74bd4308af7a548dc13a202fc55c59ea68cfe9e576738bd8ca68d8c0bb65c25501a81666b9fa6ce135ddda76e73e9ee76f6428b060ec86fa12dc9a7deda597748deef402c0fc88a38a3f8e5b0659227db242c203f7b2c42300ed0ac30209c66702e3f4cad2a2d304a4af9cda0307c44f9e9f34b172dc9ff723de1eadd483c07d20796fa2ba00728397cae8d9031cdd0c506ef664446b78ae5c2d9bf40c7490fbb1311cc5176c815009a6e72e749b08c601e6b41ad0e8e29f62785027971b785a2915dd5cfc39ef3e61aeb1a7b6354ff96c94085f62a6e2f868483476428b05821446ae7e2360d443a51595b757cad5823b1c70975248ef4bcebdd50351356d45d02610af20ea18eaf3d0e1d7a1f526bf4db3bfa0c6092d88581a35e259f27fecb1af93fd1168956839ef3b118fd71c2d4cddb505961702b58a55db6865c02daed502ec95560272ec89966b5b631d021c258c46fc1bfc0e3234b186a3887d857b402bd0899f55e4befd318dd08b3b330ad7fe764806b55b9b8b05a609bfbebe2c380473587a66998ed0ba5773c57f0d220fa480a16a79161670703a4721f0518439af76a99bc7d91d8caf0c5950ce042b84457ff9187ee0be1ef4d388e4c6b2f74be520285a428f9ec3852836d6e94389480dbed5a6115b676b92aad8bf5ae631228f989fa7c3e76d636133a2a7ae73a1a53c511b30a7dde830ab786c041012273c8d70ef4e8a960a58c871753cb69eead4452fa358aef4503261fca589a1277737bfd6a0c43e635d3cfb3d8709fc7a70f47ceff812687a03b8135fcb11b551a9391312a807bb1a9f3a89c9ca2f00f6b013a7d4a77708a03db450862182dd2731e170e49bdd89e6f0753189da05e8f049edff88ad1226620e388ba8172723adcbd8aea43c9aa7a7eb94645f42599137f8a1b9746840f716e25b94b7a3da4332eb0839aa7a020a5e64de99120d3783d818aa21a9dfeeaf3e5861195f1f45145c49a0ae6c5e67563d207a41939bf9ed6aa08a5de33419392e984e24251f84633d2950b8f94feeba5780964f286ceecb26712246b54e7828435dd66cd3759212386f43a53fb527f047b29a68cf3be207ed8e4166f9111dcacc4b597dc4c04667961e4e984d005f686bd41887f3599d9bc6d7c313caa891ddce4924055499b8b0a3de441a78080ce263cece45bfe967c5990a8c1d4e5acc2545e266fcda1080d07643818c33b753bbecc23e9b96bf009433e16703572dc7b6f5ee2c1dac225845d482836b7858f46eb9f7f48dc57e382e6ba92f5e2b31a11d51d3767f9218f0a793b3243e4987b69b60088372fdf48c7b652ff516213fac07e2c0d0143cb4f396df0d3fe9fbb44a99a622f1cd5b0ceb4fd159bf78e2aec5b175fdde3d29037c06fba6b92efa146d6eb1ba08f68555b4	f99be76ac60af2ecd59f4bbb4afca5ae3013a3606a92593553202d3ea4b86e20
authn:myConjurAccount	\\x47ab5b6a8e1245e82ed0fe7ee8a186d9d3baaaae3269faa3f9929d68c51f8f0879548152bbf8688e26c7c60476eef20325e43b65b60d5247f502928fd28a673b0b3e4db1f1972c118c31438b10c17826ae33b6b1d9ee1f982a0e5e5fbc08a6664c7f15b9b66ce718a4c9809c8c5cee5903341c1f757f7a4b332ca4e81ecc6f0c4fbf34716a8b46d33565e8a4886e342f4dc49f0aa8491af23b7863d9bae1e9449e8cdcb53be0f95278f9da5bc018af94c0b790b490862e4a1a90c90cd1c02c9e61b8060c2d6b951946b9fd8924234f14f4fd5ff4e082818cd9519dc69e3b3f7c1e8aa6fc67c01612a910fa5d08f222dbb65049ea83283b4b489f7a20970bef0abe7b67092221a0ee18a3a34b83d18336b613b7ff547b4670307cef6f3f52a24a95e72fe84a568d4ec2c29d1f73dd15d6ac948c869a4dc05bb9e45d431653835a03ca48b0d787d8355504b284611eaa9dd97e3022945c7a0cbb2d317d1810b436120a9942b7f6604e9c75c929171ee5a5703e24249180d4a0f97e48ddbdabb99abe64f8ff51dd445c9741ddc1e2d2e82ab8e98e432f482fea70fa930a73599ea5b4d7e61e0cdc18fc5ab2c9a26e4bf816af5caaf9e2e839fe41c628614f77019b0a807a9811c6af9074d3c6ae4acdf513cb870376024b404910afbbb2910ff2380836f4b7b8a5d8262a2872a1c58c86b3779f9a60498d00fe72ba6a57ff7d4a4232c3475248af4bef6857b3ae7eb7e8d822c07d9fad2c071f3afab22b32937b837c8c867769faaa5f244fe2e31093edf67f82079ceb013ac5109b1efb03764622202a2694fa0d57aa038a5bfa157b629ca8ea648048c27695e9f432aae9b39ce64101743409c611b6a4e8f9ba6c6744b1f0662b2baffa57650296fdeac80fe9c1eba5e39693ebc6f219002be0149698d1fe25853e3e35751f9ca7f53159f062489eca58c717824f7667ccdd9a7ecce4c2c418181b11281d1a5bef7250ddce9fa113fa58252fba447bead64ec0a28897c0b324a45c184ff3510fa9b978087ba7a1c85f8dbae29cee72d75081dc0c57c6fc655a464ddba8b538a8dcbb3a99bc01893ac2e5cd73e4921ebd8918604a518a433b057c8ff1d2be2dfab3058c84c7b54c5a1993dbf1cdc4e35a05b5fd115e60e6d9b40d7a1bd7769943395bb23c5606c1fcf0666829a982a26c5e45770061801b252ae0c53ae6eb8013c7dac7677038628236d141693a40da6339904dfd38f91522e396bf519557b0f688f56153488be096138589ed1084aa4d80dd895deacdc8b0224df168ae01258d3e4981b1ae3805de19b190102c5684dddb8fdcbe30527de8c778db9721c2fbda87bf39a8315f4bd68c2a433654c698f9e2e3107cdec02a2a045d8015b84383b9ac91e08ff638f170d701400fd1b124df41fed9c202814abb85a8be06b94b853f1f7e253cf4bf9bf8749965d6e5572e853efab25db1d3414ee100c9cb294c7b307ffe3f8b0cc8a54a05e257f930f019a35c4881549043f7cff3581cc7203917e7d859c7aad2d7e66bf47819f5b0508ffef2d45249147e411a742dea747dde1165e713ac888776dbc914c7a9e5ce76dfbd233c9038295b1e4139e8d4dc516cdd2e44c60e60c683a84b5f661a4ec0158a9f5ed720695690fc62d09bbafd0dd29b40abd0113629738d630b2dfd574fdd1470042a2273f7b5d3867ebd3ef3ca7c6fbd10214171094edb0882c541	da55ce54a90718c7502bca0f6ac20a579a20fa0ef837f43ddb693524b30cece8
\.


--
-- Name: authenticator_configs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.authenticator_configs_id_seq', 1, false);


--
-- PostgreSQL database dump complete
--

