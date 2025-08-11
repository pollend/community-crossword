<script lang="ts">
  import { get} from 'svelte/store';
  import SidebarContainer from './sidbarConatiner.svelte';
  import { getContext } from 'svelte';
  import ScoreWord from './score_word.svelte';
  import { Global } from './state';
  import { netSendNick } from './net';
  let { close, isOpen }: {updateNick: (nick: string) => void,close:() => void, isOpen: boolean} = $props();

  let display: string = $state('');
  let submitting: boolean = $state(false);

  const global = getContext('global') as Global;
  const {nick, num_clues, score, words_solved } = global;
  nick.subscribe(value => {
    submitting = false;
    display = value;
  });
  function closeHandler() {
    display = get(nick); // reset display to the current store value
    close();
  }

  async function submit() {
    submitting = true;
    netSendNick(global.socket!, display);
  }

</script>
<SidebarContainer
  isOpen={isOpen}
  close={closeHandler}
>
  <div class="flex items-center justify-between p-6 border-b border-black-200 text-black" >
    <h2 class="text-4xl font-headline">Profile</h2>
    <button 
      onclick={closeHandler}
      class="hover:text-black-200 transition-colors duration-200"
      aria-label="Close high scores"
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" fill="currentColor" class="bi bi-x-lg" viewBox="0 0 16 16">
        <path d="M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707l-5.146 5.147a.5.5 0 0 1-.708-.708L7.293 8z"/>
      </svg>
    </button>
  </div>
  <div class="p-6 space-y-6">
    <!-- Display Name Section -->
      <h3 class="text-lg font-semibold text-gray-900 mb-4">Display Name</h3>
      <div class="flex space-x-2">
          <input
            maxlength="62"
            type="text" 
            bind:value={display} 
            class="flex-1 bg-gray-50 border border-gray-300 text-gray-900 text-sm focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5"
            placeholder="Enter your display name"
          >
          <button 
            class="px-4 py-2.5 bg-blue-600 hover:bg-gray-400 text-white rounded-lg transition-colors duration-200 flex items-center {submitting ? 'opacity-50 cursor-not-allowed !bg-gray-400' : ''}"
            onclick={() => submit()}
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" viewBox="0 0 16 16">
              <path d="M12.736 3.97a.733.733 0 0 1 1.047 0c.286.289.29.756.01 1.05L7.88 12.01a.733.733 0 0 1-1.065.02L3.217 8.384a.757.757 0 0 1 0-1.06.733.733 0 0 1 1.047 0l3.052 3.093 5.4-6.425z"/>
            </svg>          </button>
      </div>

    <!-- Profile Statistics -->
    <h3 class="text-lg font-semibold text-gray-900 mb-4">Your Statistics</h3>
    <div class="grid grid-cols-2 gap-4">
      <div class="bg-gradient-to-br from-blue-50 to-blue-100 p-4 rounded-lg text-center">
        <div class="text-2xl font-bold text-blue-700">{$score}</div>
        <div class="text-sm text-blue-600 font-medium">Total Score</div>
      </div>
      <div class="bg-gradient-to-br from-green-50 to-green-100 p-4 rounded-lg text-center">
        <div class="text-2xl font-bold text-green-700">{$num_clues}</div>
        <div class="text-sm text-green-600 font-medium">Words Solved</div>
      </div>
    </div>

    <!-- Recent Words Solved -->
    <h3 class="text-lg font-semibold text-gray-900 mb-4">Recent Words Solved</h3>
    {#if $words_solved.length > 0}
      <div class="space-y-3 overflow-y-auto">
        {#each ($words_solved).reverse() as solve}
          <div class="bg-gray-50 p-3 border-l-4 border-blue-400">
              <div class="flex justify-between items-start mb-2">
                <ScoreWord input={solve.word}></ScoreWord>
                <div class="font-bold text-xl text-green-500"> +{solve.score}</div>
              </div>

              <div class="flex justify-between items-start mb-2">
                <div class="text-sm text-gray-700">{solve.clue}</div>
                <div class="text-xs text-gray-500">{new Date(solve.timestamp * 1000).toLocaleTimeString()}</div>
              </div>
          </div>
        {/each}
      </div>
    {:else}
      <div class="text-center text-gray-500 py-8">
        <svg class="w-12 h-12 mx-auto mb-3 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
        </svg>
        <p class="font-medium">No words solved yet!</p>
        <p class="text-sm">Start solving clues to see your progress here.</p>
      </div>
    {/if}

    <!-- Performance Insights 
    {#if $words_solved.length > 0}
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">📈 Performance Insights</h3>
        <div class="grid grid-cols-1 gap-4">
          <div class="bg-gradient-to-r from-purple-50 to-pink-50 p-4 rounded-lg">
            <div class="flex justify-between items-center">
              <span class="text-sm font-medium text-gray-700">Average Score per Word:</span>
              <span class="text-lg font-bold text-purple-700">
                {Math.round($score / $num_clues)}
              </span>
            </div>
          </div>
          <div class="bg-gradient-to-r from-orange-50 to-red-50 p-4 rounded-lg">
            <div class="flex justify-between items-center">
              <span class="text-sm font-medium text-gray-700">Most Recent Word:</span>
              <span class="text-lg font-bold text-orange-700 uppercase tracking-wide">
                {$words_solved[$words_solved.length - 1]?.word || 'None'}
              </span>
            </div>
          </div>
        </div>
      </div>
    {/if} -->
  </div>

</SidebarContainer>

