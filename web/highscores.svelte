<script lang="ts">
  import SidebarContainer from './sidbarConatiner.svelte';
  import { HighscoreTable } from './highscoreTable';
  import { getContext, onMount } from 'svelte';
  import ScoreWord from './score_word.svelte';

  let { close, isOpen }: {close:() => void, isOpen: boolean} = $props();
  
  const highscores = getContext('globalHighscores') as HighscoreTable;
  const { last_updated, entries } = highscores;

  //onMount(() => {
  //  if (isOpen) {
  //    highscores.refresh();
  //  }
  //});

  function fmtName(name: string): string {
    if(name.trim().length === 0) {
      return "anonymous";
    }
    return name;
  }

  function formatTime(date: Date): string {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function formatDate(date: Date): string {
    const now = new Date();
    const diffInDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));
    
    if (diffInDays === 0) {
      return 'Today';
    } else if (diffInDays === 1) {
      return 'Yesterday';
    } else if (diffInDays < 7) {
      return `${diffInDays} days ago`;
    } else {
      return date.toLocaleDateString();
    }
  }
</script>

<!-- Slide-out panel -->
<SidebarContainer
  isOpen={isOpen}
  close={() => close()}
>
  <div class="flex items-center justify-between p-6 border-b border-black-200 text-black" >
    <h2 class="text-4xl font-headline ">High Scores</h2>
    <button 
      onclick={close}
      class="hover:text-black-200 transition-colors duration-200"
      aria-label="Close high scores"
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" fill="currentColor" class="bi bi-x-lg" viewBox="0 0 16 16">
        <path d="M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707l-5.146 5.147a.5.5 0 0 1-.708-.708L7.293 8z"/>
      </svg>
    </button>
  </div>
  <div class="flex-1 overflow-y-auto">
  <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400 overflow-x-auto">
      <thead class="text-xs text-gray-700 uppercase bg-blue-100">
          <tr>
              <th scope="col" class="px-6 py-3">
                  # 
              </th>
              <th scope="col" class="px-6 py-3">
                Nick 
              </th>
              <th scope="col" class="px-6 py-3">
                Last Word 
              </th>
              <th scope="col" class="px-6 py-3">
                Num. Words 
              </th>
              <th scope="col" class="px-6 py-3">
                Score 
              </th>
          </tr>
      </thead>
      <tbody>
        {#each $entries as en, index}
          <tr class="bg-white border-b border-gray-200 ">
            <th scope="row" class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap border-l-4 {index === 0 ? 'border-yellow-500' : index === 1 ? 'border-gray-400' : index === 2 ? 'border-amber-600' : ''}">
                {index + 1}
            </th>
            <th scope="row" class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap">
              <h3 class="font-semibold text-gray-900 truncate max-w-32">{fmtName(en.nick)}</h3>
            </th>
            <th scope="row" class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap">
              <ScoreWord input={en.lastWord} />
            </th>
            <th scope="row" class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap">
              <span>{en.numWordsSolved} words</span>
            </th>
            <th scope="row" class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap">
              <div class="text-xl font-bold text-blue-600">{en.score}</div>
            </th>
          </tr>
        {/each}
        </tbody>
    </table>
  </div>

  <!-- Footer -->
  <div class="border-t border-gray-200 p-4 bg-gray-50">
    <div class="flex items-center justify-between text-sm text-gray-600">
      {#if $last_updated === undefined}
        <span class="animate-pulse">Unknown</span>
      {:else}
        <span>Last updated: {formatDate($last_updated)} at {formatTime($last_updated)}</span>
      {/if}
    </div>
  </div>
</SidebarContainer>
