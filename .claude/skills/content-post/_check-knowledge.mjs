import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
const slugs = ['salesforce-object-setup-guide','salesforce-reports-analysis-beginners','salesforce-permission-management-beginners'];
const { data, error } = await sb.from('contents').select('id,slug,kind,title,published_at,created_at').in('slug', slugs);
if (error) { console.error(error); process.exit(1); }
console.log(JSON.stringify(data, null, 2));
