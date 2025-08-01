<script lang="ts">
  let { visible = false}: {visible: boolean} = $props();
  
  function handleKeyPress(key: string) {
    dispatch('keypress', { key });
  }
  
  function handleBackspace() {
    dispatch('backspace');
  }
  
  function handleClose() {
    dispatch('close');
  }
</script>

{#if visible}
  <!-- Keyboard Container -->
  <div class="fixed bottom-0 left-0 right-0 bg-gray-100 border-t border-gray-300 z-50 p-4 pb-6">
    <div class="space-y-2">
      {#each [
        ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
        ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
        ['Z', 'X', 'C', 'V', 'B', 'N', 'M']
      ] as row, rowIndex}
        <div class="flex justify-center gap-1">
          {#each row as letter}
            <button
              class="
                bg-white hover:bg-gray-50 active:bg-gray-200
                border border-gray-300 rounded-lg
                text-lg font-semibold text-gray-800
                w-10 h-12 
                flex items-center justify-center
                transition-colors duration-150
                select-none
                shadow-sm hover:shadow-md
              "
              onclick={() => handleKeyPress(letter)}
            >
              {letter}
            </button>
          {/each}
        </div>
      {/each}
      
      <!-- Bottom row with special keys -->
      <div class="flex justify-center gap-2 mt-3">
        <button
          class="
            bg-gray-500 hover:bg-red-600 active:bg-red-700
            text-white font-semibold
            px-6 h-12 rounded-lg
            transition-colors duration-150
            select-none
            shadow-sm hover:shadow-md
          "
          onclick={handleBackspace}
        >
          ⌫ Back 
        </button>
        
        <button
          class="
            bg-gray-800 hover:bg-gray-600 active:bg-gray-700
            text-white font-semibold
            px-6 h-12 rounded-lg
            transition-colors duration-150
            select-none
            shadow-sm hover:shadow-md
          "
          onclick={handleClose}
        >
          Close
        </button>
      </div>
    </div>
  </div>
{/if}

<style lang="postcss">
  @reference "tailwindcss";
</style>
