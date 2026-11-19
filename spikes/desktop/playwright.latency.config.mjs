import {defineConfig} from '@playwright/test';
// Opt-in MRK-9 latency measurement. Kept out of the default suite so timing on a
// loaded machine never fails functional checks.
export default defineConfig({testDir:'.',testMatch:'latency.spec.mjs',workers:1,use:{baseURL:'http://127.0.0.1:18792',headless:true},webServer:{command:'MARKRIGHT_PREVIEW_PORT=18792 node server.mjs',url:'http://127.0.0.1:18792',reuseExistingServer:false},outputDir:'./build/latency-results',projects:[{name:'chromium',use:{browserName:'chromium'}},{name:'webkit',use:{browserName:'webkit'}}]});
