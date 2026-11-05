// SPDX-License-Identifier: MIT
// Checks an exported release tree before publication and corresponding-source packaging.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const read=p=>fs.readFileSync(path.join(root,p));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const manifest=JSON.parse(read('SOURCE_MANIFEST.json'));
// Only byte-for-byte reviewed upstream UI hints and synthetic regression fixtures
// are exempt. A changed file with the same path must pass review again.
const fixtures=JSON.parse(read('tools/public-fixtures.json'));
const fixtureHashes=new Map(fixtures.files.map(f=>[f.path,f.sha256]));
let checked=0;
for(const item of manifest.files){
 if(path.isAbsolute(item.path)||item.path.split('/').includes('..'))throw Error('Unsafe source path');
 const full=path.join(root,item.path);const b=fs.lstatSync(full).isSymbolicLink()?Buffer.from(fs.readlinkSync(full)):read(item.path);if(hash(b)!==item.sha256)throw Error('Source mismatch: '+item.path);
 if(/(?:^|\/)(?:node_modules|\.dart_tool|\.git|\.ds-bot|\.dsh)(?:\/|$)|(?:^|\/)(?:\.env|key\.properties|device\.key|\.credentials[^/]*|[^/]+\.(?:keystore|jks))$/i.test(item.path))throw Error('Private/runtime path in release source: '+item.path);
 if(b.length<3*1024*1024&&!b.includes(0)&&/(?:gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)/.test(b.toString('utf8'))&&fixtureHashes.get(item.path)!==hash(b))throw Error('Credential-shaped content in '+item.path);
 checked++;
}
if(!read('LICENSE').includes('GNU AFFERO GENERAL PUBLIC LICENSE'))throw Error('Missing root AGPL license');
if(!read('mobile/LICENSE').includes('GNU AFFERO GENERAL PUBLIC LICENSE'))throw Error('Missing mobile AGPL license');
if(!read('desktop/ds-bot/LICENSE').includes('Apache License'))throw Error('Missing DS Bot license');
if(!read('desktop/remote/packages/plugin/LICENSE').includes('MIT License'))throw Error('Missing Remote license');
if(!read('branding/LICENSE').includes('MIT License'))throw Error('Missing original artwork license');
if(!fs.existsSync(path.join(root,'desktop/ds-bot/NOTICE')))throw Error('Missing upstream NOTICE');
for(const p of ['mobile/site/home','mobile/docs/assets','mobile/app/tool/pet_src','mobile/app/tool/whale_src'])if(fs.existsSync(path.join(root,p)))throw Error('Reserved upstream marketing/art source was not excluded: '+p);
const oldArt=JSON.parse(read('UPSTREAM_ART_HASHES.json'));
let replacedArt=0;
for(const entry of oldArt.files){const full=path.join(root,'mobile',entry.path);if(!fs.existsSync(full))continue;const b=fs.readFileSync(full);const blob=crypto.createHash('sha1').update(Buffer.concat([Buffer.from('blob '+b.length),Buffer.from([0]),b])).digest('hex');if(blob===entry.gitBlob)throw Error('Unreplaced reserved upstream artwork: '+entry.path);replacedArt++;}
const intake=read('.github/workflows/pr-intake.yml').toString('utf8');
if(!intake.includes('pull_request_target:')||intake.includes('actions/checkout')||!intake.includes("state: 'closed'"))throw Error('PR intake workflow must close external PRs without checking them out');
console.log(JSON.stringify({checkedSourceFiles:checked,licenses:'present',privatePaths:'absent',reservedArtworkFilesReplaced:replacedArt,prIntake:'owner-only, no external checkout'}));
