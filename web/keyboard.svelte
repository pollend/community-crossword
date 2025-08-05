<script lang="ts">
  import { clickOutside } from './clickOutside';
  let { visible = false, keypress, backpress, close }: {visible: boolean, backpress: () => void, keypress: (c: string) => void, close:() => void} = $props();
</script>

{#if visible}
  <!-- Keyboard Container -->
  <div class="fixed bottom-0 left-0 right-0 bg-gray-100 border-t border-gray-300 z-50 p-4 pb-6" use:clickOutside onClickOutside={close}>
    <div class="space-y-2">
      {#each [
        ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
        ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
        ['Z', 'X', 'C', 'V', 'B', 'N', 'M']
      ] as row}
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
              onclick={() => keypress(letter)}
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
          onclick={() => backpress()}
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
          onclick={() => close()}
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
