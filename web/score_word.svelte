<script lang="ts">
    import { isEmptyValue, Value, valueToChar, wordValue } from "./net";
    let {input }: {input: Value[]} = $props();
</script>
                
<div class="text-xl font-semibold text-gray-900 uppercase tracking-wide">
  {#each input as letter}
    <span class="relative">
      {valueToChar(letter)}
      {#if !isEmptyValue(letter || 0)}
        <span class="absolute -top-2 -right-0 text-xs text-gray-500 font-thin">
          { wordValue(letter)}
        </span>
      {/if}
    </span>
  {/each}
</div>

