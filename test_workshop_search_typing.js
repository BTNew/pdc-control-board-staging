'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const source=fs.readFileSync('workshop-planner.js','utf8');
const inputHandler=source.slice(source.indexOf("searchInput?.addEventListener('input'"),source.indexOf("searchInput?.addEventListener('keydown'"));
assert(inputHandler.includes('workshopRefreshSearchResults(root, input, input.value)'),'Debounced typing must refresh only the search results');
assert(!inputHandler.includes('workshopRevealSearchMatch'),'Debounced typing must not invoke the full planner render path');
assert(!inputHandler.includes('renderWorkshopPlanner'),'Debounced typing must preserve the current input element and focus');
const refresh=source.slice(source.indexOf('function workshopRefreshSearchResults('),source.indexOf('function workshopPartsSummary('));
assert(refresh.includes('results.innerHTML ='),'Search results must update in place');
assert(refresh.includes("control?.classList.toggle('is-open'"),'Search control open state must update in place');
assert(refresh.includes("input?.setAttribute('aria-expanded'"),'Search accessibility state must update in place');
assert(refresh.includes('workshopBindSearchResultButtons(root)'),'Newly rendered search result buttons must remain interactive');
assert(!refresh.includes('renderWorkshopPlanner()'),'In-place search refresh must not replace the focused input');
console.log('Workshop planner uninterrupted search typing contract passed');
