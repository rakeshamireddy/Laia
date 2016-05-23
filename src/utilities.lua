--[[
   a = {1, 2, 3, 4}
   table.reduce(a, function(x) return 2* x; end)
   {2, 4, 6, 8}
--]]
table.map = function(t, fn)
   local t2 = {}
   for i, v in pairs(t) do
      t2[i] = fn(v)
   end
   return t2
end

--[[
   a = {1, 2, 3, 4}
   table.reduce(a, operator.add, 0)
   10
--]]
table.reduce = function(t, fn, v0)
   local res = v0
   for _, v in pairs(t) do
      res = fn(res, v)
   end
   return res
end

--[[
   Compute a histogram of the absolute values of the elements in a tensor,
   using a logarithmic scale.
   The function returs first a table containing the histogram (the number of
   elements in each bin), and secondly a table containing the thresholds for
   each bin.
--]]
torch.loghistc = function(x, nbins, bmin, bmax)
   x = torch.abs(x)
   nbins = nbins or 10
   bmin = bmin or torch.min(x)
   bmax = bmax or torch.max(x)
   if bmin == 0.0 then bmin = 1E-16 end
   assert(nbins > 1,
    string.format('nbins must be greater than 1 (actual: %d)', nbins))
   assert(bmax > bmin,
    string.format('bmax (%g) must be greater than bmin (%g)', bmax, bmin))
   local hist = { }
   local bins = { }
   local step = math.exp(math.log(bmax / bmin) / (nbins - 1))
   table.insert(bins, bmin)
   table.insert(hist, torch.le(x, bmin):sum())
   for i=1,(nbins-1) do
      local pb = bmin * math.pow(step, i - 1)
      local cb = pb * step
      table.insert(bins, cb)
      table.insert(hist, torch.cmul(torch.gt(x, pb), torch.le(x, cb)):sum())
   end
   -- Due to numerical errors, we may miss some elements in the last bin.
   local cumhist = table.reduce(hist, operator.add, 0)
   local missing = x:storage():size() - cumhist
   if missing > 0 then
      hist[#hist] = hist[#hist] + missing
   end
   return hist, bins
end

torch.sumarizeMagnitudes = function(x, mass, nbins, bmin, bmax, log_scale)
   mass = mass or 0.75
   log_scale = log_scale or true
   local hist, bins
   if log_scale then
      hist, bins = torch.loghistc(x, nbins, bmin, bmax)
   else
      x = torch.abs(x)
      bmin = bmin or torch.min(x)
      bmax = bmax or torch.max(x)
      hist = torch.totable(torch.histc(x, nbins, bmin, bmax))
      bins = torch.totable(torch.range(bmin, bmax, (bmax - bmin) / (nbins - 1)))
   end
   local n = x:storage():size()
   local aux = {}
   for i=1,#hist do table.insert(aux, {i, hist[i]})  end
   table.sort(aux,
        function(a, b)
     return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1])
              end)
   local cum = 0
   local mini = #aux
   local maxi = 0
   for i=1,#aux do
      cum = cum + aux[i][2]
      if mini > aux[i][1] then mini = aux[i][1] end
      if maxi < aux[i][1] then maxi = aux[i][1] end
      if cum >= mass * n then break end
   end
   if mini < 2 then
      return torch.min(torch.abs(x)), bins[maxi], cum / n
   else
      return bins[mini - 1], bins[maxi], cum / n
   end
end

function levenshtein(u, v)
  -- create two tables of distances
  local prev = {}
  local curr = {}

  -- Operations: {SUB, DEL, INS}
  prev_ops = {}
  curr_ops = {}
  for i=0, #v, 1 do
   curr[i] = i

   curr_ops[i]={}

   curr_ops[i]['SUB'] = 0
   curr_ops[i]['DEL'] = 0
   curr_ops[i]['INS'] = i
  end

  for x=1, #u, 1 do
   prev = curr
   curr = {}

   prev_ops = curr_ops
   curr_ops = {}

   curr[0] = x
   curr_ops[0] = {}
   curr_ops[0]['SUB'] = 0
   curr_ops[0]['DEL'] = x
   curr_ops[0]['INS'] = 0
   
   for i=1, #v, 1 do
    curr_ops[i]={}
   end
   
   for y=1, #v, 1 do
    --local cost = (s[i] == t[j] and 0 or 1)
    local delcost = prev[y] + 1 
    local addcost = curr[y-1] + 1
    local subcost = prev[y-1] + (u[x] ~= v[y] and 1 or 0)
    
    curr[y] = math.min(subcost, delcost, addcost)

    if curr[y] == subcost then
      curr_ops[y]['SUB'] = prev_ops[y-1]['SUB'] + (u[x] ~= v[y] and 1 or 0)
      curr_ops[y]['DEL'] = prev_ops[y-1]['DEL']
      curr_ops[y]['INS'] = prev_ops[y-1]['INS']
    elseif curr[y] == delcost then
      curr_ops[y]['SUB'] = prev_ops[y]['SUB'] 
      curr_ops[y]['DEL'] = prev_ops[y]['DEL'] + 1
      curr_ops[y]['INS'] = prev_ops[y]['INS']        
    else
      curr_ops[y]['SUB'] = curr_ops[y-1]['SUB'] 
      curr_ops[y]['DEL'] = curr_ops[y-1]['DEL']
      curr_ops[y]['INS'] = curr_ops[y-1]['INS'] + 1
    end
   end
  end
  return curr[#v], curr_ops[#v]
end

function printHistogram(x, nbins, bmin, bmax)
  local hist, bins = torch.loghistc(x, nbins, bmin, bmax)
  local n = x:storage():size()
  io.write(string.format('(-inf, %g] -> %.2g%%\n',
        bins[1], 100 * hist[1] / n))
  for i=2,#hist do
   io.write(string.format('(%g, %g] -> %.2g%%\n',
          bins[i-1], bins[i], 100 * hist[i] / n))
  end
end

function framewise_decode(batch_size, rnn_output)
  local hyps = {};

  -- Initialize hypotheses for each batch element
  for i=1,batch_size do
    table.insert(hyps, {})
  end
  -- Put hypotheses with non repeated symbols
  local hyps = {};
  for t=1,#rnn_output do
    local _, idx = torch.max(rnn_output[t], 2)
    --print(idx[1])
    idx = torch.totable(idx - 1)
    --print(idx, _)
    for i=1,batch_size do
      if i <= #hyps then
        table.insert(hyps[i], idx[i][1])
      else
        hyps[i] = idx[i];
      end
    end
---    print(hyps)
  end
  local hyps2 = {}
  for i=1,batch_size do
    table.insert(hyps2, {})
    for t=1,#hyps[i] do
      is_ok = true
      -- if blank -> do not add 
      if hyps[i][t] == 0 then
        is_ok = false
      end
      -- if previous symbol is the same -> do not add
      if hyps[i][t] == hyps2[i][#hyps2[i]] then
        is_ok = false
      end      
      if is_ok then
        table.insert(hyps2[i], hyps[i][t])
      end
    end
  end
  return hyps2
end