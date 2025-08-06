<script lang="ts">
  import SidebarContainer from './sidbarConatiner.svelte';
  import { clickOutside } from './clickOutside';

  interface PlayerScore {
    nick: string;
    score: number;
    wordsCompleted: number;
    lastWordSolved: string;
    timestamp: Date;
  }
  let { close, isOpen }: {close:() => void, isOpen: boolean} = $props();

  let scores: PlayerScore[] = [

  ];

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
  <!-- Header -->
  <div class="flex items-center justify-between p-6 border-b border-gray-200 bg-gradient-to-r from-blue-600 to-purple-600 text-white" >
    <h2 class="text-2xl font-bold">🏆 High Scores</h2>
    <button 
      onclick={close}
      class="text-white hover:text-gray-200 transition-colors duration-200"
      aria-label="Close high scores"
    >
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
  </div>

  <!-- Content -->
  <div class="flex-1 overflow-y-auto p-6">
    {#if scores.length === 0}
      <div class="text-center text-gray-500 mt-8">
        <svg class="w-16 h-16 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
        </svg>
        <p class="text-lg font-medium">No scores yet!</p>
        <p class="text-sm">Be the first to complete some words.</p>
      </div>
    {:else}
      <div class="space-y-3">
        {#each scores as player, index}
          <div class="bg-gray-50 rounded-lg p-4 hover:bg-gray-100 transition-colors duration-200 border border-gray-200">
            <!-- Rank and Player Info -->
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center space-x-3">
                <!-- Rank Badge -->
                <div class="flex-shrink-0">
                  {#if index === 0}
                    <span class="inline-flex items-center justify-center w-8 h-8 bg-yellow-500 text-white rounded-full text-sm font-bold">🥇</span>
                  {:else if index === 1}
                    <span class="inline-flex items-center justify-center w-8 h-8 bg-gray-400 text-white rounded-full text-sm font-bold">🥈</span>
                  {:else if index === 2}
                    <span class="inline-flex items-center justify-center w-8 h-8 bg-amber-600 text-white rounded-full text-sm font-bold">🥉</span>
                  {:else}
                    <span class="inline-flex items-center justify-center w-8 h-8 bg-gray-300 text-gray-700 rounded-full text-sm font-bold">#{index + 1}</span>
                  {/if}
                </div>
                
                <!-- Player Name -->
                <div>
                  <h3 class="font-semibold text-gray-900 truncate max-w-32">{player.nick}</h3>
                  <p class="text-xs text-gray-500">{formatDate(player.timestamp)}</p>
                </div>
              </div>
              
              <!-- Score -->
              <div class="text-right">
                <div class="text-xl font-bold text-blue-600">{player.score}</div>
                <div class="text-xs text-gray-500">points</div>
              </div>
            </div>
            
            <!-- Stats -->
            <div class="flex justify-between items-center text-sm text-gray-600 border-t border-gray-200 pt-2">
              <div class="flex items-center space-x-4">
                <div class="flex items-center space-x-1">
                  <span class="text-green-600">✓</span>
                  <span>{player.wordsCompleted} words</span>
                </div>
                <div class="text-xs text-gray-400">
                  {formatTime(player.timestamp)}
                </div>
              </div>
            </div>
            
            <!-- Last Word Solved -->
            {#if player.lastWordSolved}
              <div class="mt-2 pt-2 border-t border-gray-200">
                <div class="text-xs text-gray-500 mb-1">Last word solved:</div>
                <div class="text-sm font-medium text-gray-700 bg-white px-2 py-1 rounded border">
                  "{player.lastWordSolved}"
                </div>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Footer -->
  <div class="border-t border-gray-200 p-4 bg-gray-50">
    <div class="flex items-center justify-between text-sm text-gray-600">
      <span>{scores.length} player{scores.length !== 1 ? 's' : ''}</span>
      <span>Updated just now</span>
    </div>
  </div>
</SidebarContainer>
