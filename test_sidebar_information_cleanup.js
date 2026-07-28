'use strict';
const fs=require('fs');
const pages=['index.html','staging.html','no-vehicles.html','test-50.html','test-75.html','test-100.html'];
for(const page of pages){const html=fs.readFileSync(page,'utf8');for(const removed of ['id="report-date"','id="report-meta"','id="operational-health-summary"','operational-health-card']){if(html.includes(removed))throw new Error(`${page} still renders removed sidebar information: ${removed}`);}if(!html.includes('<aside class="sidebar"'))throw new Error(`${page} sidebar navigation is missing`);}
console.log('Sidebar source-data and operational-health cleanup passed');
